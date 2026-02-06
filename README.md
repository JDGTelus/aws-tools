# aws-tools

A professional, interactive CLI utility for managing AWS workflows with CodeCommit and CodePipeline.

## Description

`aws-tools` is a bash-based wrapper around the AWS CLI that provides a friendly, interactive terminal interface for common AWS CodeCommit and CodePipeline operations. It streamlines your workflow by allowing you to:

- Switch between AWS SSO profiles easily
- Browse and select CodeCommit repositories
- View and review pull requests with detailed information
- Monitor CodePipeline executions and approval requirements
- Cache data for faster subsequent access

The tool is read-only and provides viewing capabilities along with the exact AWS CLI commands needed to perform actions like approving PRs or pipeline stages.

## Features

- **Profile Management**: Interactive selection from your `~/.aws/config` profiles with SSO support
- **Repository Browser**: List and select CodeCommit repositories in the current account
- **Pull Request Viewer**: 
  - List open PRs with count
  - View detailed PR information (title, author, branches, description)
  - Display approval rules and status
  - Show exact commands for approve/decline/merge operations
- **Pipeline Monitor**: 
  - View pipeline execution status
  - Stage-by-stage breakdown with action details
  - Identify approval requirements with tokens
  - Display commands for approval/rejection
- **Data Caching**: 
  - Caches repository info, PRs, and pipeline states
  - Shows cache timestamps (e.g., "2m ago", "5h ago")
  - Option to view cached data or refresh from AWS
- **State Persistence**: Remembers your last profile, repository, and pipeline selections
- **Professional CLI**: Color-coded output, clean formatting, intuitive navigation

## Prerequisites

- `aws` - AWS CLI v2 with SSO configured
- `jq` - JSON processor
- `bash` - Version 4.0 or higher

## Installation

Make the script executable:

```bash
chmod +x aws-tools
```

Optionally, add to your PATH:

```bash
ln -s $(pwd)/aws-tools /usr/local/bin/aws-tools
```

## Usage

Run the tool:

```bash
./aws-tools
```

### Main Workflow

1. **Switch AWS Profile** - Select from your configured profiles
2. **Browse CodeCommit Repositories** - Choose a repository to work with
3. **View Pull Requests** or **Repository Information**
4. **Browse CodePipelines** - Monitor pipeline executions

### Working with Pull Requests

- Select a repository (or it auto-enters if previously selected)
- Choose "View Pull Requests"
- See count and decide whether to load details or use cached data
- Select a specific PR to view full details including approval instructions

### Working with Pipelines

- Select a pipeline (or it auto-enters if previously selected)
- View pipeline status with stage breakdown
- See cached data or refresh from AWS
- Get exact commands for approving stages that require approval

### Data Storage

The tool stores configuration and cache in `~/.aws-tools/`:

- `state` - Current profile, repository, and pipeline selections
- `cache/` - Cached AWS data (repository info, PRs, pipeline states)
  - Format: JSON files with timestamps
  - Example: `repo_info_sh-code-base-dev_my-repo.json`

### Example Commands Provided

For PR approval:
```bash
aws codecommit update-pull-request-approval-state \
  --pull-request-id <pr-id> \
  --revision-id <revision-id> \
  --approval-state APPROVE
```

For pipeline stage approval:
```bash
aws codepipeline put-approval-result \
  --pipeline-name <pipeline-name> \
  --stage-name <stage-name> \
  --action-name <approval-action-name> \
  --result summary="Approved",status=Approved \
  --token <approval-token>
```

## Security

- No credentials are stored or modified
- Uses your existing AWS CLI configuration
- Read-only operations - does not modify AWS resources
- Approval operations must be performed manually via displayed commands

## Color Legend

- **Green (✓)**: Success, completed operations
- **Yellow (⚠)**: Warnings, in-progress states, actions required
- **Red (✗)**: Errors, failed operations
- **Blue (ℹ)**: Informational messages
- **Cyan**: Headers and interactive prompts
- **Dim**: Secondary information, cached timestamps
