package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Output is the top-level JSON written to stdout.
type Output struct {
	Codex  CodexUsage  `json:"codex"`
	Claude ClaudeUsage `json:"claude"`
}

// CodexUsage is the Codex usage data for the bar widget.
type CodexUsage struct {
	Available bool        `json:"available"`
	Stale     bool        `json:"stale"`
	PlanType  string      `json:"plan_type"`
	Primary   UsageWindow `json:"primary"`
	Secondary UsageWindow `json:"secondary"`
	Credits   *Credits    `json:"credits"`
	Source    string      `json:"source"`
}

type UsageWindow struct {
	Pct           float64 `json:"pct"`
	ResetAt       int64   `json:"reset_at"`
	WindowSeconds int64   `json:"window_seconds"`
}

type Credits struct {
	HasCredits bool    `json:"has_credits"`
	Balance    float64 `json:"balance"`
}

// FlexibleFloat accepts a JSON number or a numeric string.
type FlexibleFloat float64

func (f *FlexibleFloat) UnmarshalJSON(data []byte) error {
	var n float64
	if err := json.Unmarshal(data, &n); err == nil {
		*f = FlexibleFloat(n)
		return nil
	}
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		if _, err := fmt.Sscanf(s, "%f", &n); err == nil {
			*f = FlexibleFloat(n)
		}
		return nil
	}
	return nil
}

// --- wham/usage OAuth API response ---

type whamUsageResponse struct {
	PlanType  string `json:"plan_type"`
	RateLimit struct {
		PrimaryWindow   whamRateWindow `json:"primary_window"`
		SecondaryWindow whamRateWindow `json:"secondary_window"`
	} `json:"rate_limit"`
	Credits *struct {
		HasCredits bool         `json:"has_credits"`
		Unlimited  bool         `json:"unlimited"`
		Balance    FlexibleFloat `json:"balance"`
	} `json:"credits"`
}

type whamRateWindow struct {
	UsedPercent        float64 `json:"used_percent"`
	ResetAt            int64   `json:"reset_at"`
	LimitWindowSeconds int64   `json:"limit_window_seconds"`
}

// --- websocket event (logs_2.sqlite fallback) ---

type wsEvent struct {
	Type       string `json:"type"`
	PlanType   string `json:"plan_type"`
	RateLimits *struct {
		Allowed       bool          `json:"allowed"`
		LimitReached  bool          `json:"limit_reached"`
		Primary       wsRateWindow  `json:"primary"`
		Secondary     wsRateWindow  `json:"secondary"`
	} `json:"rate_limits"`
}

type wsRateWindow struct {
	UsedPercent       float64 `json:"used_percent"`
	WindowMinutes     int64   `json:"window_minutes"`
	ResetAfterSeconds int64   `json:"reset_after_seconds"`
	ResetAt           int64   `json:"reset_at"`
}

const (
	oauthClientID    = "app_EMoamEEZ73f0CkXaXp7hrann"
	oauthTokenURL    = "https://auth.openai.com/oauth/token"
	defaultBaseURL   = "https://chatgpt.com/backend-api/"
	tokenMaxAge      = 8 * 24 * time.Hour
	httpTimeout      = 10 * time.Second
	wsEventPrefix    = "websocket event: "
)

// fetchCodexUsage tries OAuth API, then logs_2.sqlite, then cache.
func fetchCodexUsage(codexHome string) CodexUsage {
	cacheDir := getCacheDir()

	usage, err := tryOAuthAPI(codexHome)
	if err == nil {
		usage.Source = "oauth-api"
		_ = saveCache(cacheDir, &usage)
		return usage
	}
	log.Printf("oauth api: %v", err)

	usage, err = tryLogsDB(codexHome)
	if err == nil {
		usage.Source = "logs-sqlite"
		_ = saveCache(cacheDir, &usage)
		return usage
	}
	log.Printf("logs sqlite: %v", err)

	cached, err := loadCache(cacheDir)
	if err == nil {
		cached.Stale = true
		cached.Source = "cache"
		return *cached
	}

	return CodexUsage{Available: false}
}

// tryOAuthAPI reads auth.json, refreshes if stale, calls wham/usage.
func tryOAuthAPI(codexHome string) (CodexUsage, error) {
	authPath := filepath.Join(codexHome, "auth.json")
	raw, err := os.ReadFile(authPath)
	if err != nil {
		return CodexUsage{}, fmt.Errorf("read auth.json: %w", err)
	}

	var auth map[string]interface{}
	if err := json.Unmarshal(raw, &auth); err != nil {
		return CodexUsage{}, fmt.Errorf("parse auth.json: %w", err)
	}

	tokens, ok := auth["tokens"].(map[string]interface{})
	if !ok {
		return CodexUsage{}, fmt.Errorf("no tokens in auth.json")
	}

	accessToken := getString(tokens, "access_token")
	if accessToken == "" {
		return CodexUsage{}, fmt.Errorf("no access_token")
	}
	accountID := getString(tokens, "account_id")

	if needsRefresh(auth) && getString(tokens, "refresh_token") != "" {
		if err := refreshToken(auth); err == nil {
			_ = saveAuth(authPath, auth)
			tokens = auth["tokens"].(map[string]interface{})
			accessToken = getString(tokens, "access_token")
			accountID = getString(tokens, "account_id")
		}
	}

	baseURL := loadConfigBaseURL(codexHome)
	resp, err := fetchWhamUsage(accessToken, accountID, baseURL)
	if err != nil {
		return CodexUsage{}, err
	}

	return mapWhamResponse(resp), nil
}

func getString(m map[string]interface{}, key string) string {
	v, ok := m[key]
	if !ok || v == nil {
		return ""
	}
	s, ok := v.(string)
	if !ok {
		return ""
	}
	return s
}

func needsRefresh(auth map[string]interface{}) bool {
	lastRefresh, ok := auth["last_refresh"].(string)
	if !ok || lastRefresh == "" {
		return true
	}
	t, err := time.Parse(time.RFC3339, lastRefresh)
	if err != nil {
		t, err = time.Parse(time.RFC3339Nano, lastRefresh)
		if err != nil {
			return true
		}
	}
	return time.Since(t) > tokenMaxAge
}

func refreshToken(auth map[string]interface{}) error {
	tokens, ok := auth["tokens"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("no tokens")
	}
	rt := getString(tokens, "refresh_token")
	if rt == "" {
		return fmt.Errorf("no refresh_token")
	}

	body := map[string]string{
		"client_id":     oauthClientID,
		"grant_type":    "refresh_token",
		"refresh_token": rt,
		"scope":         "openid profile email",
	}
	bodyJSON, _ := json.Marshal(body)

	client := &http.Client{Timeout: httpTimeout}
	resp, err := client.Post(oauthTokenURL, "application/json", bytes.NewReader(bodyJSON))
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("token refresh HTTP %d: %s", resp.StatusCode, string(b))
	}

	var tr struct {
		IDToken      string `json:"id_token"`
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tr); err != nil {
		return err
	}

	tokens["id_token"] = tr.IDToken
	tokens["access_token"] = tr.AccessToken
	tokens["refresh_token"] = tr.RefreshToken
	auth["last_refresh"] = time.Now().UTC().Format(time.RFC3339)
	return nil
}

func saveAuth(authPath string, auth map[string]interface{}) error {
	data, err := json.MarshalIndent(auth, "", "  ")
	if err != nil {
		return err
	}
	perm := os.FileMode(0600)
	if info, err := os.Stat(authPath); err == nil {
		perm = info.Mode().Perm()
	}
	tmp := authPath + ".tmp"
	if err := os.WriteFile(tmp, data, perm); err != nil {
		return err
	}
	return os.Rename(tmp, authPath)
}

func loadConfigBaseURL(codexHome string) string {
	data, err := os.ReadFile(filepath.Join(codexHome, "config.toml"))
	if err != nil {
		return defaultBaseURL
	}
	re := regexp.MustCompile(`chatgpt_base_url\s*=\s*"([^"]+)"`)
	m := re.FindStringSubmatch(string(data))
	if len(m) >= 2 {
		return m[1]
	}
	return defaultBaseURL
}

func fetchWhamUsage(accessToken, accountID, baseURL string) (*whamUsageResponse, error) {
	url := strings.TrimRight(baseURL, "/") + "/wham/usage"

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "dms-ai-usage/0.1")
	if accountID != "" {
		req.Header.Set("ChatGPT-Account-Id", accountID)
	}

	client := &http.Client{Timeout: httpTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("wham/usage HTTP %d: %s", resp.StatusCode, string(b))
	}

	var usage whamUsageResponse
	if err := json.NewDecoder(resp.Body).Decode(&usage); err != nil {
		return nil, fmt.Errorf("decode wham/usage: %w", err)
	}
	return &usage, nil
}

func mapWhamResponse(resp *whamUsageResponse) CodexUsage {
	u := CodexUsage{
		Available: true,
		PlanType:  resp.PlanType,
		Primary: UsageWindow{
			Pct:           resp.RateLimit.PrimaryWindow.UsedPercent,
			ResetAt:       resp.RateLimit.PrimaryWindow.ResetAt,
			WindowSeconds: resp.RateLimit.PrimaryWindow.LimitWindowSeconds,
		},
		Secondary: UsageWindow{
			Pct:           resp.RateLimit.SecondaryWindow.UsedPercent,
			ResetAt:       resp.RateLimit.SecondaryWindow.ResetAt,
			WindowSeconds: resp.RateLimit.SecondaryWindow.LimitWindowSeconds,
		},
	}
	if resp.Credits != nil {
		u.Credits = &Credits{
			HasCredits: resp.Credits.HasCredits,
			Balance:    float64(resp.Credits.Balance),
		}
	}
	return u
}

// tryLogsDB reads the latest codex.rate_limits websocket event from logs_2.sqlite.
func tryLogsDB(codexHome string) (CodexUsage, error) {
	dbPath := filepath.Join(codexHome, "logs_2.sqlite")
	if _, err := os.Stat(dbPath); err != nil {
		return CodexUsage{}, fmt.Errorf("logs_2.sqlite: %w", err)
	}

	query := "SELECT feedback_log_body FROM logs WHERE target = 'codex_api::endpoint::responses_websocket' AND feedback_log_body LIKE '%codex.rate_limits%' ORDER BY ts DESC LIMIT 1"

	cmd := exec.Command("sqlite3", dbPath, query)
	output, err := cmd.Output()
	if err != nil {
		return CodexUsage{}, fmt.Errorf("sqlite3: %w", err)
	}

	body := strings.TrimSpace(string(output))
	if body == "" {
		return CodexUsage{}, fmt.Errorf("no rate_limits events")
	}

	event, err := parseWebsocketEvent(body)
	if err != nil {
		return CodexUsage{}, err
	}
	if event.RateLimits == nil {
		return CodexUsage{}, fmt.Errorf("rate_limits is null")
	}

	return CodexUsage{
		Available: true,
		PlanType:  event.PlanType,
		Primary: UsageWindow{
			Pct:           event.RateLimits.Primary.UsedPercent,
			ResetAt:       event.RateLimits.Primary.ResetAt,
			WindowSeconds: event.RateLimits.Primary.WindowMinutes * 60,
		},
		Secondary: UsageWindow{
			Pct:           event.RateLimits.Secondary.UsedPercent,
			ResetAt:       event.RateLimits.Secondary.ResetAt,
			WindowSeconds: event.RateLimits.Secondary.WindowMinutes * 60,
		},
	}, nil
}

func parseWebsocketEvent(body string) (*wsEvent, error) {
	idx := strings.LastIndex(body, wsEventPrefix)
	if idx < 0 {
		return nil, fmt.Errorf("no websocket event in log body")
	}
	jsonStr := strings.TrimSpace(body[idx+len(wsEventPrefix):])
	dec := json.NewDecoder(strings.NewReader(jsonStr))
	var event wsEvent
	if err := dec.Decode(&event); err != nil {
		return nil, fmt.Errorf("parse websocket JSON: %w", err)
	}
	return &event, nil
}

// --- cache ---

func getCacheDir() string {
	if xdg := os.Getenv("XDG_CACHE_HOME"); xdg != "" {
		return filepath.Join(xdg, "dms-ai-usage")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".cache", "dms-ai-usage")
}

func saveCache(dir string, usage *CodexUsage) error {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	data, err := json.Marshal(usage)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "codex.json"), data, 0644)
}

func loadCache(dir string) (*CodexUsage, error) {
	data, err := os.ReadFile(filepath.Join(dir, "codex.json"))
	if err != nil {
		return nil, err
	}
	var usage CodexUsage
	if err := json.Unmarshal(data, &usage); err != nil {
		return nil, err
	}
	return &usage, nil
}
