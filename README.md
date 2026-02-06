# aws-tools

A professional, interactive CLI utility for managing AWS CodeCommit and CodePipeline workflows with copy-paste ready approval commands.

## Description

`aws-tools` is a bash wrapper around the AWS CLI that provides a friendly, interactive terminal interface for common AWS operations. It streamlines your workflow by caching data for quick access and generating ready-to-use commands with all required parameters pre-filled.

## Features

- **Profile Management**: Interactive selection from your `~/.aws/config` profiles with SSO support
- **Repository Browser**: List and select CodeCommit repositories in the current account
- **Pull Request Viewer**:
  - List open PRs with count and caching
  - View detailed PR information (title, author, branches, description, revision ID)
  - Display approval rules and status
  - **Copy-paste ready commands** with all values filled in (approve, decline, merge)
- **Pipeline Monitor**:
  - View pipeline execution status with stage breakdown
  - Display execution tokens and commit IDs
  - Identify approval requirements with tokens
  - **Copy-paste ready approval/rejection commands** for each pending approval
- **Data Caching**:
  - Caches repository info, PRs, and pipeline states locally
  - Shows cache timestamps (e.g., "2m ago", "5h ago") for data freshness awareness
  - Option to view cached data instantly or refresh from AWS
  - Cache stored as JSON in `~/.aws-tools/cache/`
- **State Persistence**: Remembers your last profile, repository, and pipeline selections across sessions
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
4. **Browse CodePipelines** - Monitor pipeline executions and approvals

### Pull Request Approval Workflow

When you view a PR, the tool displays complete information including the revision ID, and provides ready-to-use commands:

```bash
# All values are filled in - just copy and paste:
aws codecommit update-pull-request-approval-state \
  --pull-request-id 123 \
  --revision-id abc123def456 \
  --approval-state APPROVE
```

The tool also provides commands for declining and merging PRs with all required parameters.

### Pipeline Approval Workflow

When viewing a pipeline with pending approvals, the tool shows:

1. Pipeline status with all stages
2. Pending approvals clearly marked
3. Complete approval/rejection commands for each pending approval

Example output:

```bash
Stage: Deploy-Production - Action: ManualApproval

To APPROVE:
  aws codepipeline put-approval-result \
    --pipeline-name my-pipeline \
    --stage-name "Deploy-Production" \
    --action-name "ManualApproval" \
    --result summary="Approved via aws-tools",status=Approved \
    --token "abc123-def456-789"
```

Simply copy, optionally customize the summary, and paste to approve.

### Data Storage

The tool stores configuration and cache in `~/.aws-tools/`:

- `state` - Current profile, repository, and pipeline selections
- `cache/` - Cached AWS data (repository info, PRs, pipeline states)
  - Format: JSON files with timestamps
  - Example: `repo_info_sh-code-base-dev_my-repo.json`
  - Example: `prs_sh-code-base-dev_my-repo.json`
  - Example: `pipeline_sh-cicd-ro_my-pipeline.json`

## Key Features in Detail

### Copy-Paste Ready Commands

All approval commands are generated with actual values from AWS:
- **PR approvals**: Includes revision ID (fetched automatically)
- **Pipeline approvals**: Includes stage name, action name, and approval token
- **No manual lookup required**: All parameters are filled in and ready to use

### Intelligent Caching

- View data instantly from cache
- See exactly when data was last fetched
- Refresh on demand when you need current data
- Cache organized by profile and resource name

### Seamless Navigation

- Auto-enters repository/pipeline menu if already selected
- Resilient error handling with recovery options
- Returns to menu instead of exiting on errors
- Profile/repository context always visible

## Security

- No credentials are stored or modified
- Uses your existing AWS CLI configuration
- Read-only operations - does not modify AWS resources
- Approval operations must be performed manually via displayed commands

## Color Legend

- **Green (✓)**: Success, completed operations
- **Yellow (⚠)**: Warnings, in-progress states, approvals required
- **Red (✗)**: Errors, failed operations
- **Blue (ℹ)**: Informational messages
- **Cyan**: Headers, commands, interactive prompts
- **Dim**: Secondary information, cache timestamps
