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

	codex := fetchCodexUsage(home)

	out := Output{Codex: codex}
	data, err := json.Marshal(out)
	if err != nil {
		fmt.Fprintf(os.Stderr, "json marshal error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println(string(data))
}
