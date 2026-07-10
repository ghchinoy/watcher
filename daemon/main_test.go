package main

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"strings"
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

func TestSanitizeEnvValue(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"normal-actor", "normal-actor"},
		{"actor\nwith\nnewlines", "actorwithnewlines"},
		{"actor\rwith\rcarriage", "actorwithcarriage"},
		{"actor\x00with\x00nulls", "actorwithnulls"},
		{"actor\n\r\x00mixed", "actormixed"},
	}

	for _, tc := range tests {
		got := sanitizeEnvValue(tc.input)
		if got != tc.expected {
			t.Errorf("sanitizeEnvValue(%q) = %q; want %q", tc.input, got, tc.expected)
		}
	}
}

func TestCommentsFlagInjection(t *testing.T) {
	originalWd, err := os.Getwd()
	if err != nil {
		t.Fatalf("Failed to get working directory: %v", err)
	}
	defer func() {
		_ = os.Chdir(originalWd)
	}()

	err = os.Chdir("..")
	if err != nil {
		t.Fatalf("Failed to change directory to project root: %v", err)
	}

	var buf bytes.Buffer
	outputWriter = &buf

	ctx := context.Background()
	req := Request{
		Method: "get_comments",
		Params: json.RawMessage(`{"id": "--force"}`),
		ID:     123,
	}

	dispatchRequest(ctx, nil, req)

	var resp Response
	if err := json.Unmarshal(buf.Bytes(), &resp); err != nil {
		t.Fatalf("Failed to unmarshal response: %v. Output: %q", err, buf.String())
	}

	if resp.ID != 123 {
		t.Errorf("Expected ID 123, got %v", resp.ID)
	}

	if resp.Error == nil {
		t.Fatalf("Expected Error in response, got nil (Result: %v)", resp.Result)
	}

	expectedSub := `resolving --force`
	if !strings.Contains(resp.Error.Message, expectedSub) {
		t.Errorf("Expected error message to contain %q, got %q", expectedSub, resp.Error.Message)
	}

	// Double check that it did NOT report unknown flag
	unexpectedSub := "unknown flag"
	if strings.Contains(resp.Error.Message, unexpectedSub) {
		t.Errorf("Flag injection occurred! Error message contained %q, output: %q", unexpectedSub, resp.Error.Message)
	}
}
