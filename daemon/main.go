package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/steveyegge/beads"
)

type Request struct {
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
	ID     int             `json:"id"`
}

type Response struct {
	JSONRPC string      `json:"jsonrpc"`
	Result  interface{} `json:"result,omitempty"`
	Error   *Error      `json:"error,omitempty"`
	ID      int         `json:"id"`
}

type Error struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func sendError(id int, code int, message string) {
	resp := Response{
		JSONRPC: "2.0",
		Error: &Error{
			Code:    code,
			Message: message,
		},
		ID: id,
	}
	sendResponse(resp)
}

func sendResponse(resp Response) {
	bytes, err := json.Marshal(resp)
	if err != nil {
		log.Fatalf("Failed to marshal response: %v", err)
	}
	fmt.Printf("%s\n", string(bytes))
}

func handleGraph(ctx context.Context, storage beads.Storage, id int) {
	// Query all open issues, or modify filter as needed
	filter := beads.IssueFilter{}
	nodes, err := storage.SearchIssues(ctx, "", filter)
	if err != nil {
		sendError(id, -32000, fmt.Sprintf("failed to get issues: %v", err))
		return
	}
	
	// Create JSON representation of the graph
	// We might need to wrap nodes or adapt to the exact JSON struct Dart expects
	// For now, return the nodes directly
	
	resp := Response{
		JSONRPC: "2.0",
		Result:  nodes,
		ID:      id,
	}
	sendResponse(resp)
}


func main() {
	if len(os.Args) < 2 {
		log.Fatalf("Usage: %s <path-to-repo>", os.Args[0])
	}
	repoPath := os.Args[1]

	ctx := context.Background()
	
	// Initialize database connection
	// We just change into the repoPath so FindBeadsDir works contextually,
	// or we pass it directly. Since beads.FindBeadsDir uses current directory, we chdir.
	if err := os.Chdir(repoPath); err != nil {
		log.Fatalf("Failed to chdir to %s: %v", repoPath, err)
	}

	beadsDir := beads.FindBeadsDir()
	if beadsDir == "" {
		log.Fatalf("Failed to find beads database in %s", repoPath)
	}

	storage, err := beads.OpenFromConfig(ctx, beadsDir)
	if err != nil {
		log.Fatalf("Failed to open beads database: %v", err)
	}
	defer storage.Close()

	// Simple stdin/stdout JSON-RPC loop
	decoder := json.NewDecoder(os.Stdin)
	for {
		var req Request
		if err := decoder.Decode(&req); err != nil {
			if err.Error() == "EOF" {
				break
			}
			// Send parse error
			sendError(0, -32700, "Parse error")
			continue
		}

		switch req.Method {
		case "graph":
			handleGraph(ctx, storage, req.ID)
		case "ping":
			sendResponse(Response{JSONRPC: "2.0", Result: "pong", ID: req.ID})
		default:
			sendError(req.ID, -32601, "Method not found")
		}
	}
}
