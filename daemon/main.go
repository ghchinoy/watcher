package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
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

type remoteReader interface {
	ListRemotes(ctx context.Context) ([]struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	}, error)
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
	var params struct {
		Peer string `json:"peer"` // optional, if empty syncs all
	}
	// We ignore unmarshal errors here since params might be empty/null
	json.Unmarshal(req.Params, &params)

	// In beads v0.60.0, true sync is exposed via SyncStore
	type syncStore interface {
		Sync(ctx context.Context, peer string, strategy string) (interface{}, error)
	}

	if ss, ok := storage.(syncStore); ok {
		var err error
		if params.Peer != "" {
			_, err = ss.Sync(ctx, params.Peer, "theirs")
		} else {
			// If no peer specified, we'll try 'cloud' which is our synthetic peer
			// or we could loop through all peers from handleGetPeers
			// For now, let's just attempt to sync "cloud"
			_, err = ss.Sync(ctx, "cloud", "theirs")
		}

		if err != nil {
			sendError(req.ID, -32000, fmt.Sprintf("failed to sync peer: %v", err))
			return
		}

		sendResponse(Response{
			JSONRPC: "2.0",
			Result:  "ok",
			ID:      req.ID,
		})
		return
	}

	// Fallback to dolt push/pull if Sync() isn't available
	type remoteStore interface {
		PullFrom(ctx context.Context, peer string) ([]interface{}, error)
		PushTo(ctx context.Context, peer string) error
		Pull(ctx context.Context) error
		Push(ctx context.Context) error
	}

	if rs, ok := storage.(remoteStore); ok {
		var err error
		if params.Peer != "" && params.Peer != "cloud" {
			_, err = rs.PullFrom(ctx, params.Peer)
			if err == nil {
				err = rs.PushTo(ctx, params.Peer)
			}
		} else {
			err = rs.Pull(ctx)
			if err == nil {
				err = rs.Push(ctx)
			}
		}

		if err != nil {
			sendError(req.ID, -32000, fmt.Sprintf("failed to sync peer: %v", err))
			return
		}

		sendResponse(Response{
			JSONRPC: "2.0",
			Result:  "ok",
			ID:      req.ID,
		})
		return
	}

	sendError(req.ID, -32601, "Storage backend does not support remotes or sync")
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

	sendResponse(Response{
		JSONRPC: "2.0",
		Result:  "ok",
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
			// Send parse error
			sendError(0, -32700, "Parse error")
			continue
		}

		switch req.Method {
		case "graph":
			handleGraph(ctx, storage, req.ID)
		case "create_issue":
			handleCreateIssue(ctx, storage, req)
		case "update_issue":
			handleUpdateIssue(ctx, storage, req)
		case "close_issue":
			handleCloseIssue(ctx, storage, req)
		case "get_peers":
			handleGetPeers(ctx, storage, req)
		case "add_peer":
			handleAddPeer(ctx, storage, req)
		case "sync_peer":
			handleSyncPeer(ctx, storage, req)
		case "ping":
			sendResponse(Response{JSONRPC: "2.0", Result: "pong", ID: req.ID})
		default:
			sendError(req.ID, -32601, "Method not found")
		}
	}
}
