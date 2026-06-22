package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
)

func main() {
	log.SetFlags(0)

	codexHome := flag.String("codex-home", "", "Path to Codex home directory (default: $CODEX_HOME or ~/.codex)")
	claudeHome := flag.String("claude-home", "", "Path to Claude Code home directory (default: $CLAUDE_HOME or ~/.claude)")
	flag.Parse()

	home := *codexHome
	if home == "" {
		home = os.Getenv("CODEX_HOME")
	}
	if home == "" {
		h, err := os.UserHomeDir()
		if err != nil {
			fmt.Fprintf(os.Stderr, "cannot determine home directory: %v\n", err)
			os.Exit(1)
		}
		home = filepath.Join(h, ".codex")
	}

	chome := *claudeHome
	if chome == "" {
		chome = os.Getenv("CLAUDE_HOME")
	}
	if chome == "" {
		h, err := os.UserHomeDir()
		if err != nil {
			fmt.Fprintf(os.Stderr, "cannot determine home directory: %v\n", err)
			os.Exit(1)
		}
		chome = filepath.Join(h, ".claude")
	}

	codex := fetchCodexUsage(home)
	claude := fetchClaudeUsage(chome)

	out := Output{Codex: codex, Claude: claude}
	data, err := json.Marshal(out)
	if err != nil {
		fmt.Fprintf(os.Stderr, "json marshal error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println(string(data))
}
