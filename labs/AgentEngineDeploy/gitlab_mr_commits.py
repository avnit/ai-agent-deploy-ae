
import argparse
import os

# This is a mock GitLab tool.
# In a real scenario, this would be a proper GitLab API client.
class MockGitLab:
    def get_merge_request_commits(self, project_id, merge_request_iid):
        print(f"Fetching commits for project {project_id} and merge request {merge_request_iid}")
        # In a real scenario, you would make an API call to GitLab here.
        # For this example, we'll return some mock data.
        return [
            {
                "sha": "a1b2c3d4",
                "title": "feat: Add new feature",
                "author": "John Doe",
                "date": "2025-12-09T10:00:00Z",
            },
            {
                "sha": "e5f6g7h8",
                "title": "fix: Correct a bug",
                "author": "Jane Smith",
                "date": "2025-12-09T11:30:00Z",
            },
        ]

def main():
    parser = argparse.ArgumentParser(description="Fetch and display commits from a GitLab merge request.")
    parser.add_argument("project_id", help="The ID of the GitLab project.")
    parser.add_argument("merge_request_iid", help="The IID of the merge request.")
    args = parser.parse_args()

    # In a real application, you would initialize your GitLab client here.
    gitlab = MockGitLab()

    commits = gitlab.get_merge_request_commits(args.project_id, args.merge_request_iid)

    if commits:
        print("Commits (in chronological order):")
        for commit in sorted(commits, key=lambda c: c['date']):
            print(f"  - SHA: {commit['sha']}")
            print(f"    Title: {commit['title']}")
            print(f"    Author: {commit['author']}")
            print(f"    Date: {commit['date']}")
    else:
        print("No commits found for this merge request.")

if __name__ == "__main__":
    main()
