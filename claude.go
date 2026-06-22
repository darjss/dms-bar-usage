package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

// ClaudeUsage is the Claude Code usage data for the bar widget, sourced from
// Anthropic's (undocumented) OAuth usage endpoint.
type ClaudeUsage struct {
	Available     bool         `json:"available"`
	Stale         bool         `json:"stale"`
	PlanType      string       `json:"plan_type"`
	RateLimitTier string       `json:"rate_limit_tier"`
	Primary       UsageWindow  `json:"primary"`
	Secondary     UsageWindow  `json:"secondary"`
	ModelSpecific *ModelWindow `json:"model_specific"`
	ExtraUsage    *ExtraUsage  `json:"extra_usage"`
	Source        string       `json:"source"`
}

// ModelWindow is a model-scoped weekly limit window (e.g. Sonnet, Opus).
type ModelWindow struct {
	Label         string  `json:"label"`
	Pct           float64 `json:"pct"`
	ResetAt       int64   `json:"reset_at"`
	WindowSeconds int64   `json:"window_seconds"`
}

// ExtraUsage mirrors the extra_usage / spend credits block from the API.
type ExtraUsage struct {
	IsEnabled      bool    `json:"is_enabled"`
	MonthlyLimit   float64 `json:"monthly_limit"`
	UsedCredits    float64 `json:"used_credits"`
	Utilization    float64 `json:"utilization"`
	DisabledReason string  `json:"disabled_reason"`
}

// claudeUsageResponse is the observed shape of
// https://api.anthropic.com/api/oauth/usage (2026-06). Window keys are null
// when the account has no relevant limit; unknown keys are ignored by Go's
// decoder.
type claudeUsageResponse struct {
	FiveHour          *claudeWindow `json:"five_hour"`
	SevenDay          *claudeWindow `json:"seven_day"`
	SevenDayOpus      *claudeWindow `json:"seven_day_opus"`
	SevenDaySonnet    *claudeWindow `json:"seven_day_sonnet"`
	SevenDayOAuthApps *claudeWindow `json:"seven_day_oauth_apps"`
	ExtraUsage        *claudeExtra  `json:"extra_usage"`
}

type claudeWindow struct {
	Utilization float64 `json:"utilization"`
	ResetsAt    string  `json:"resets_at"`
}

type claudeExtra struct {
	IsEnabled      bool    `json:"is_enabled"`
	MonthlyLimit   float64 `json:"monthly_limit"`
	UsedCredits    float64 `json:"used_credits"`
	Utilization    float64 `json:"utilization"`
	DisabledReason string  `json:"disabled_reason"`
}

type claudeCredentials struct {
	ClaudeAiOauth struct {
		AccessToken      string `json:"accessToken"`
		SubscriptionType string `json:"subscriptionType"`
		RateLimitTier    string `json:"rateLimitTier"`
	} `json:"claudeAiOauth"`
}

const (
	claudeUsageURL   = "https://api.anthropic.com/api/oauth/usage"
	claudeBetaHeader = "oauth-2025-04-20"
	claudeUserAgent  = "claude-cli/2.1.175 (external, cli)"
	sevenDaySeconds  = 7 * 24 * 3600
	fiveHourSeconds  = 5 * 3600
)

// fetchClaudeUsage tries the OAuth usage endpoint, then cache.
func fetchClaudeUsage(claudeHome string) ClaudeUsage {
	cacheDir := getCacheDir()

	usage, err := tryClaudeOAuth(claudeHome)
	if err == nil {
		usage.Source = "oauth-api"
		_ = saveClaudeCache(cacheDir, &usage)
		return usage
	}
	log.Printf("claude oauth api: %v", err)

	cached, err := loadClaudeCache(cacheDir)
	if err == nil {
		cached.Stale = true
		cached.Source = "cache"
		return *cached
	}

	return ClaudeUsage{Available: false}
}

func tryClaudeOAuth(claudeHome string) (ClaudeUsage, error) {
	credPath := filepath.Join(claudeHome, ".credentials.json")
	raw, err := os.ReadFile(credPath)
	if err != nil {
		return ClaudeUsage{}, fmt.Errorf("read .credentials.json: %w", err)
	}

	var creds claudeCredentials
	if err := json.Unmarshal(raw, &creds); err != nil {
		return ClaudeUsage{}, fmt.Errorf("parse .credentials.json: %w", err)
	}
	if creds.ClaudeAiOauth.AccessToken == "" {
		return ClaudeUsage{}, fmt.Errorf("no accessToken in .credentials.json")
	}

	resp, err := fetchClaudeUsageAPI(creds.ClaudeAiOauth.AccessToken)
	if err != nil {
		return ClaudeUsage{}, err
	}

	return mapClaudeResponse(resp, creds), nil
}

func fetchClaudeUsageAPI(token string) (*claudeUsageResponse, error) {
	req, err := http.NewRequest("GET", claudeUsageURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("anthropic-beta", claudeBetaHeader)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", claudeUserAgent)

	client := &http.Client{Timeout: httpTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("claude usage HTTP %d: %s", resp.StatusCode, string(b))
	}

	var usage claudeUsageResponse
	if err := json.NewDecoder(resp.Body).Decode(&usage); err != nil {
		return nil, fmt.Errorf("decode claude usage: %w", err)
	}
	return &usage, nil
}

func mapClaudeResponse(resp *claudeUsageResponse, creds claudeCredentials) ClaudeUsage {
	u := ClaudeUsage{
		Available:     true,
		PlanType:      creds.ClaudeAiOauth.SubscriptionType,
		RateLimitTier: creds.ClaudeAiOauth.RateLimitTier,
		Primary: UsageWindow{
			WindowSeconds: fiveHourSeconds,
		},
		Secondary: UsageWindow{
			WindowSeconds: sevenDaySeconds,
		},
	}
	if resp.FiveHour != nil {
		u.Primary.Pct = resp.FiveHour.Utilization
		u.Primary.ResetAt = parseISO8601ToUnix(resp.FiveHour.ResetsAt)
	}
	if resp.SevenDay != nil {
		u.Secondary.Pct = resp.SevenDay.Utilization
		u.Secondary.ResetAt = parseISO8601ToUnix(resp.SevenDay.ResetsAt)
	}
	// Prefer the most specific non-null model window: Sonnet, then Opus, then
	// OAuth apps. Only attach when the window actually carries data.
	if w := firstNonNilModelWindow(resp); w != nil {
		u.ModelSpecific = w
	}
	if resp.ExtraUsage != nil {
		u.ExtraUsage = &ExtraUsage{
			IsEnabled:      resp.ExtraUsage.IsEnabled,
			MonthlyLimit:   resp.ExtraUsage.MonthlyLimit,
			UsedCredits:    resp.ExtraUsage.UsedCredits,
			Utilization:    resp.ExtraUsage.Utilization,
			DisabledReason: resp.ExtraUsage.DisabledReason,
		}
	}
	return u
}

func firstNonNilModelWindow(resp *claudeUsageResponse) *ModelWindow {
	switch {
	case resp.SevenDaySonnet != nil && hasData(resp.SevenDaySonnet):
		return &ModelWindow{Label: "Sonnet", Pct: resp.SevenDaySonnet.Utilization,
			ResetAt: parseISO8601ToUnix(resp.SevenDaySonnet.ResetsAt), WindowSeconds: sevenDaySeconds}
	case resp.SevenDayOpus != nil && hasData(resp.SevenDayOpus):
		return &ModelWindow{Label: "Opus", Pct: resp.SevenDayOpus.Utilization,
			ResetAt: parseISO8601ToUnix(resp.SevenDayOpus.ResetsAt), WindowSeconds: sevenDaySeconds}
	case resp.SevenDayOAuthApps != nil && hasData(resp.SevenDayOAuthApps):
		return &ModelWindow{Label: "OAuth Apps", Pct: resp.SevenDayOAuthApps.Utilization,
			ResetAt: parseISO8601ToUnix(resp.SevenDayOAuthApps.ResetsAt), WindowSeconds: sevenDaySeconds}
	}
	return nil
}

func hasData(w *claudeWindow) bool {
	return w != nil && (w.Utilization > 0 || w.ResetsAt != "")
}

func parseISO8601ToUnix(s string) int64 {
	if s == "" {
		return 0
	}
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		t, err = time.Parse(time.RFC3339, s)
		if err != nil {
			return 0
		}
	}
	return t.Unix()
}

func saveClaudeCache(dir string, usage *ClaudeUsage) error {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	data, err := json.Marshal(usage)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "claude.json"), data, 0644)
}

func loadClaudeCache(dir string) (*ClaudeUsage, error) {
	data, err := os.ReadFile(filepath.Join(dir, "claude.json"))
	if err != nil {
		return nil, err
	}
	var usage ClaudeUsage
	if err := json.Unmarshal(data, &usage); err != nil {
		return nil, err
	}
	return &usage, nil
}
