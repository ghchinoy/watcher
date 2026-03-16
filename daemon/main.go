package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/steveyegge/beads"
	"gopkg.in/yaml.v3"
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

func handleAddPeer(ctx context.Context, storage beads.Storage, req Request) {
	var params struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	}
	if err := json.Unmarshal(req.Params, &params); err != nil {
		sendError(req.ID, -32602, "Invalid params")
		return
	}

	type remoteStore interface {
		AddRemote(ctx context.Context, name, url string) error
	}

	if rs, ok := storage.(remoteStore); ok {
		if err := rs.AddRemote(ctx, params.Name, params.URL); err != nil {
			sendError(req.ID, -32000, fmt.Sprintf("failed to add peer: %v", err))
			return
		}
		sendResponse(Response{
			JSONRPC: "2.0",
			Result:  "ok",
			ID:      req.ID,
		})
		return
	}

	sendError(req.ID, -32601, "Storage backend does not support remotes")
}

func handleSyncPeer(ctx context.Context, storage beads.Storage, req Request) {
	// Execute 'bd federation sync' via shell to leverage the CLI's robust remote
	// handling (including GCS gs:// plugins and auth) without battling unexported Go interfaces.
	cmd := exec.CommandContext(ctx, "bd", "federation", "sync")
	
	// Ensure it runs in the correct directory. FindBeadsDir starts from CWD.
	beadsDir := beads.FindBeadsDir()
	if beadsDir != "" {
		cmd.Dir = filepath.Dir(beadsDir) // The repo root
	}

	out, err := cmd.CombinedOutput()
	if err != nil {
		sendError(req.ID, -32000, fmt.Sprintf("bd federation sync failed: %v\nOutput: %s", err, string(out)))
		return
	}

	sendResponse(Response{
		JSONRPC: "2.0",
		Result:  "ok",
		ID:      req.ID,
	})
}

func handleGetPeers(ctx context.Context, storage beads.Storage, req Request) {
	type RemoteInfo struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	}
	var peers []RemoteInfo

	// Read config.yaml directly to find federation.remote
	beadsDir := beads.FindBeadsDir()
	if beadsDir != "" {
		configPath := filepath.Join(beadsDir, "config.yaml")
		data, err := os.ReadFile(configPath)
		if err == nil {
			var config struct {
				Federation struct {
					Remote string `yaml:"remote"`
				} `yaml:"federation"`
			}
			if yaml.Unmarshal(data, &config) == nil && config.Federation.Remote != "" {
				peers = append(peers, RemoteInfo{
					Name: "cloud",
					URL:  config.Federation.Remote,
				})
			}
		}
	}

	sendResponse(Response{
		JSONRPC: "2.0",
		Result:  peers,
		ID:      req.ID,
	})
}

func handleCreateIssue(ctx context.Context, storage beads.Storage, req Request) {
	var params struct {
		Issue beads.Issue `json:"issue"`
		Actor string      `json:"actor"`
	}
	if err := json.Unmarshal(req.Params, &params); err != nil {
		sendError(req.ID, -32602, "Invalid params")
		return
	}

	err := storage.CreateIssue(ctx, &params.Issue, params.Actor)
	if err != nil {
		sendError(req.ID, -32000, fmt.Sprintf("failed to create issue: %v", err))
		return
	}

	// Trigger a background export so .beads/backup/events.jsonl updates, 
	// which notifies the UI file watcher that changes occurred.
	_ = exec.Command("bd", "export").Run()

	sendResponse(Response{
		JSONRPC: "2.0",
		Result:  params.Issue.ID,
		ID:      req.ID,
	})
}

func handleCloseIssue(ctx context.Context, storage beads.Storage, req Request) {
	var params struct {
		ID      string `json:"id"`
		Reason  string `json:"reason"`
		Actor   string `json:"actor"`
		Session string `json:"session"`
	}
	if err := json.Unmarshal(req.Params, &params); err != nil {
		sendError(req.ID, -32602, "Invalid params")
		return
	}

	err := storage.CloseIssue(ctx, params.ID, params.Reason, params.Actor, params.Session)
	if err != nil {
		sendError(req.ID, -32000, fmt.Sprintf("failed to close issue: %v", err))
		return
	}

	// Trigger a background export so .beads/backup/events.jsonl updates, 
	// which notifies the UI file watcher that changes occurred.
	_ = exec.Command("bd", "export").Run()

	sendResponse(Response{
		JSONRPC: "2.0",
		Result:  "ok",
		ID:      req.ID,
	})
}

func handleGetComments(ctx context.Context, storage beads.Storage, req Request) {
        var params struct {
                ID string `json:"id"`
        }
        if err := json.Unmarshal(req.Params, &params); err != nil {
                sendError(req.ID, -32602, "Invalid params")
                return
        }

        // Because beads/internal/types is internal, we shell out to bd comments --json
        cmd := exec.Command("bd", "comments", params.ID, "--json")
        out, err := cmd.Output()
        if err != nil {
                sendError(req.ID, -32000, fmt.Sprintf("failed to get comments: %v", string(out)))
                return
        }

        var comments []interface{}
        if len(out) > 0 {
                if err := json.Unmarshal(out, &comments); err != nil {
                        sendError(req.ID, -32000, "failed to parse comments JSON")
                        return
                }
        }

        sendResponse(Response{
                JSONRPC: "2.0",
                Result:  comments,
                ID:      req.ID,
        })
}

func handleAddComment(ctx context.Context, storage beads.Storage, req Request) {
        var params struct {
                ID      string `json:"id"`
                Actor   string `json:"actor"`
                Comment string `json:"comment"`
        }
        if err := json.Unmarshal(req.Params, &params); err != nil {
                sendError(req.ID, -32602, "Invalid params")
                return
        }

        cmd := exec.Command("bd", "comments", "add", params.ID, params.Comment)
        // Pass actor down to the command
        cmd.Env = append(os.Environ(), fmt.Sprintf("BD_ACTOR=%s", params.Actor))
        
        if out, err := cmd.CombinedOutput(); err != nil {
                sendError(req.ID, -32000, fmt.Sprintf("failed to add comment: %v - %s", err, string(out)))
                return
        }

        sendResponse(Response{
                JSONRPC: "2.0",
                Result:  "ok",
                ID:      req.ID,
        })
}

func handleUpdateIssue(ctx context.Context, storage beads.Storage, req Request) {
	var params struct {
		ID      string                 `json:"id"`
		Updates map[string]interface{} `json:"updates"`
		Actor   string                 `json:"actor"`
	}
	if err := json.Unmarshal(req.Params, &params); err != nil {
		sendError(req.ID, -32602, "Invalid params")
		return
	}

	err := storage.UpdateIssue(ctx, params.ID, params.Updates, params.Actor)
	if err != nil {
		sendError(req.ID, -32000, fmt.Sprintf("failed to update issue: %v", err))
		return
	}

	// Trigger a background export so .beads/backup/events.jsonl updates, 
	// which notifies the UI file watcher that changes occurred.
	_ = exec.Command("bd", "export").Run()

	sendResponse(Response{
		JSONRPC: "2.0",
		Result:  "ok",
		ID:      req.ID,
	})
}

type depReader interface {
	GetDependencyRecordsForIssues(ctx context.Context, issueIDs []string) (map[string][]*beads.Dependency, error)
}

func handleGraph(ctx context.Context, storage beads.Storage, id int) {
	// Use SearchIssues to fetch everything (empty query, empty filter)
	filter := beads.IssueFilter{}
	nodes, err := storage.SearchIssues(ctx, "", filter)
	if err != nil {
		sendError(id, -32000, fmt.Sprintf("failed to search issues: %v", err))
		return
	}

	var allDeps map[string][]*beads.Dependency
	if dr, ok := storage.(depReader); ok {
		issueIDs := make([]string, len(nodes))
		for i, n := range nodes {
			issueIDs[i] = n.ID
		}
		allDeps, _ = dr.GetDependencyRecordsForIssues(ctx, issueIDs)
	}

	type issueWithDeps struct {
		*beads.Issue
		Dependencies []*beads.Dependency `json:"dependencies,omitempty"`
	}

	result := make([]issueWithDeps, len(nodes))
	for i, n := range nodes {
		result[i] = issueWithDeps{
			Issue:        n,
			Dependencies: allDeps[n.ID],
		}
	}

	sendResponse(Response{
		JSONRPC: "2.0",
		Result:  result,
		ID:      id,
	})
}


func main() {
	if len(os.Args) < 2 {
		log.Fatalf("Usage: %s <path-to-repo>", os.Args[0])
	}
	repoPath := os.Args[1]

	ctx := context.Background()
	
	// Initialize database connection
	// We just change into the repoPath so FindBeadsDir works contextually,
	if err := os.Chdir(repoPath); err != nil {
		log.Printf("Failed to chdir to %s: %v", repoPath, err)
		os.Exit(1)
	}

	beadsDir := beads.FindBeadsDir()
	if beadsDir == "" {
		// Output a clean JSON-RPC error instead of panic so Dart doesn't crash
		// We do this by printing a raw JSON response to stdout before exiting.
		fmt.Printf(`{"jsonrpc":"2.0","error":{"code":-32000,"message":"Directory is not a valid beads project: missing .beads folder"},"id":1}` + "\n")
		os.Exit(0)
	}

	// Emit a special bootstrapping notification so the UI knows we are
	// establishing the database connection and might be waiting for the Dolt server.
	fmt.Printf(`{"jsonrpc":"2.0","method":"boot_status","params":{"status":"connecting_to_database"}}` + "\n")

	// Proactively kill any orphaned dolt sql-server processes on the system
	// that might be holding a dead port or a dead file lock before we attempt to connect.
	// We shell out to 'bd dolt killall' since doltserver is an internal package.
	killCmd := exec.Command("bd", "dolt", "killall")
	killCmd.Dir = repoPath
	if out, err := killCmd.CombinedOutput(); err == nil {
		// Just log it internally; it's a helpful sanity check
		log.Printf("Cleaned up orphaned servers: %s", string(out))
	}

	storage, err := beads.OpenFromConfig(ctx, beadsDir)
	if err != nil {
		// Serialize the error properly so newlines in err.Error() don't break JSON structure
		errResp := Response{
			JSONRPC: "2.0",
			Error: &Error{
				Code:    -32000,
				Message: fmt.Sprintf("Failed to open beads database: %v", err),
			},
			ID: 1,
		}
		bytes, _ := json.Marshal(errResp)
		fmt.Printf("%s\n", string(bytes))
		os.Exit(0)
	}
	defer func() {
		if err := storage.Close(); err != nil {
			log.Printf("Error closing storage: %v", err)
		}
	}()

	// Simple stdin/stdout JSON-RPC loop
	decoder := json.NewDecoder(os.Stdin)
	for {
		var req Request
		if err := decoder.Decode(&req); err != nil {
			if err.Error() == "EOF" {
				break
			}
			sendError(-1, -32700, "Parse error")
			continue
		}

		switch req.Method {
		case "graph":
			handleGraph(ctx, storage, req.ID)
		case "create_issue":
			handleCreateIssue(ctx, storage, req)
		case "update_issue":
			handleUpdateIssue(ctx, storage, req)
		case "get_comments":
			handleGetComments(ctx, storage, req)
		case "add_comment":
			handleAddComment(ctx, storage, req)
		case "close_issue":
			handleCloseIssue(ctx, storage, req)
		case "get_peers":
			handleGetPeers(ctx, storage, req)
		case "add_peer":
			handleAddPeer(ctx, storage, req)
		case "sync_peer":
			handleSyncPeer(ctx, storage, req)
		case "get_version":
			sendResponse(Response{JSONRPC: "2.0", Result: "v0.61.0", ID: req.ID})
		case "ping":
			sendResponse(Response{JSONRPC: "2.0", Result: "pong", ID: req.ID})
		default:
			sendError(req.ID, -32601, "Method not found")
		}
	}
}
