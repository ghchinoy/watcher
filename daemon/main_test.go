package main

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"

	"github.com/steveyegge/beads"
)

type mockStorage struct {
	beads.Storage
	mockSearchIssues func(ctx context.Context, query string, filter beads.IssueFilter) ([]*beads.Issue, error)
}

func (m *mockStorage) SearchIssues(ctx context.Context, query string, filter beads.IssueFilter) ([]*beads.Issue, error) {
	if m.mockSearchIssues != nil {
		return m.mockSearchIssues(ctx, query, filter)
	}
	return nil, nil
}

func TestPingMethod(t *testing.T) {
	// Set up output capture
	var buf bytes.Buffer
	outputWriter = &buf

	ctx := context.Background()
	req := Request{
		Method: "ping",
		ID:     42,
	}

	dispatchRequest(ctx, nil, req)

	var resp Response
	if err := json.Unmarshal(buf.Bytes(), &resp); err != nil {
		t.Fatalf("Failed to unmarshal response: %v. Output: %q", err, buf.String())
	}

	if resp.JSONRPC != "2.0" {
		t.Errorf("Expected jsonrpc 2.0, got %s", resp.JSONRPC)
	}

	if resp.ID != 42 {
		t.Errorf("Expected ID 42, got %d", resp.ID)
	}

	if resp.Result != "pong" {
		t.Errorf("Expected Result 'pong', got %v", resp.Result)
	}
}

func TestGraphMethod(t *testing.T) {
	var buf bytes.Buffer
	outputWriter = &buf

	mockIssues := []*beads.Issue{
		{
			ID:        "issue-1",
			Title:     "Test Issue",
			Status:    "open",
			Priority:  1,
			IssueType: "task",
		},
	}

	storage := &mockStorage{
		mockSearchIssues: func(ctx context.Context, query string, filter beads.IssueFilter) ([]*beads.Issue, error) {
			if !filter.IncludeDependencies {
				t.Errorf("Expected IncludeDependencies to be true")
			}
			return mockIssues, nil
		},
	}

	ctx := context.Background()
	req := Request{
		Method: "graph",
		ID:     99,
	}

	dispatchRequest(ctx, storage, req)

	var resp Response
	if err := json.Unmarshal(buf.Bytes(), &resp); err != nil {
		t.Fatalf("Failed to unmarshal response: %v. Output: %q", err, buf.String())
	}

	if resp.ID != 99 {
		t.Errorf("Expected ID 99, got %d", resp.ID)
	}

	// Result should contain the issues
	resultBytes, err := json.Marshal(resp.Result)
	if err != nil {
		t.Fatalf("Failed to marshal result: %v", err)
	}

	var parsedIssues []beads.Issue
	if err := json.Unmarshal(resultBytes, &parsedIssues); err != nil {
		t.Fatalf("Failed to unmarshal result issues: %v", err)
	}

	if len(parsedIssues) != 1 {
		t.Fatalf("Expected 1 issue in result, got %d", len(parsedIssues))
	}

	if parsedIssues[0].ID != "issue-1" {
		t.Errorf("Expected issue ID 'issue-1', got %s", parsedIssues[0].ID)
	}
}
