#!/usr/bin/env ruby
# GitHub approval verification and pre-launch dry run only. Never starts a task.
require_relative 'automation_dispatch'

module AutomationGitHubApproval
  PILOT_ID = 'routing-doc-consistency-audit'
  PILOT_TITLE = 'Audit routing documentation consistency'
  PILOT_GOAL = 'Read the routing policy, handoff, next-task envelope, and automation scripts; report inconsistencies without editing files, committing, pushing, or dispatching.'
  PILOT_FILES = %w[
    AUTOMATION_POLICY.md CURRENT_HANDOFF.md NEXT_TASK.md
    scripts/automation_decision.rb scripts/automation_dispatch.rb scripts/automation_github_approval.rb
  ].freeze
  PILOT_FORBIDDEN = %w[
    ios/calorietracker/** ios/calorietrackerTests/** ios/calorietrackerUITests/**
    ios/calorietracker.xcodeproj/**
  ].freeze
  PILOT_VALIDATION = ['Report inspected files and contradictions; confirm zero writes and zero dispatches.'].freeze
  PILOT_STOP = ['Any write, product/test scope, ambiguity, stale approval, or changed Git state.'].freeze
  MAX_MINUTES = 15
  REPO = 'unukaaa/fud-ai'

  # The only live transport. gh uses its authenticated GitHub session; no
  # caller-provided JSON or webhook payload is accepted as authoritative.
  class GitHubClient
    QUERY = 'query($id: ID!) { node(id: $id) { ... on IssueComment { id lastEditedAt } } }'

    def fetch_issue_comment(repo:, comment_id:)
      path = "/repos/#{repo}/issues/comments/#{comment_id}"
      comment = request('gh', 'api', '--method', 'GET', '-H', 'Accept: application/vnd.github+json', path)
      node_id = comment['node_id']
      raise AutomationDecision::Invalid, 'GitHub comment missing node ID' unless node_id.is_a?(String) && !node_id.empty?
      graphql = request('gh', 'api', 'graphql', '-f', "query=#{QUERY}", '-F', "id=#{node_id}")
      raise AutomationDecision::Invalid, 'GitHub GraphQL query failed' unless graphql['errors'].nil?
      { 'comment' => comment, 'node' => graphql.dig('data', 'node') }
    end

    private

    def request(*args)
      output, _error, status = Open3.capture3(*args)
      raise AutomationDecision::Invalid, 'authenticated GitHub API request failed' unless status.success?
      JSON.parse(output)
    rescue Errno::ENOENT, JSON::ParserError
      raise AutomationDecision::Invalid, 'authenticated GitHub API unavailable or invalid'
    end
  end

  def self.stop(reason)
    AutomationDispatch.stop([reason]).merge('approval_status' => 'STOP: HOLD')
  end

  def self.pilot_task?(task)
    task['task_id'] == PILOT_ID && task['title'] == PILOT_TITLE && task['goal'] == PILOT_GOAL &&
      task['allowed_files'] == PILOT_FILES && task['forbidden_files'] == PILOT_FORBIDDEN &&
      task['validation_required'] == PILOT_VALIDATION && task['stop_conditions'] == PILOT_STOP &&
      task['commit_allowed'] == false && task['push_allowed'] == false
  end

  def self.approval_text(task_digest:, head:, expires_at:)
    "FOOD-AI GREEN APPROVAL v1\n" \
      "task_id: #{PILOT_ID}\n" \
      "task_digest: #{task_digest}\n" \
      "head: #{head}\n" \
      "expires_at: #{expires_at}\n" \
      "commit_allowed: false\n" \
      'push_allowed: false'
  end

  def self.parse_body(body)
    return nil unless body.is_a?(String)
    pattern = /\AFOOD-AI GREEN APPROVAL v1\ntask_id: (#{Regexp.escape(PILOT_ID)})\ntask_digest: ([0-9a-f]{64})\nhead: ([0-9a-f]{40})\nexpires_at: (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\ncommit_allowed: false\npush_allowed: false\n?\z/
    match = pattern.match(body)
    match && { 'task_id' => match[1], 'task_digest' => match[2], 'head' => match[3], 'expires_at' => match[4] }
  end

  def self.verify_snapshot(snapshot, repo:, issue_number:, comment_id:, approver_id:, task:, head:, now:)
    return nil unless snapshot.is_a?(Hash)
    comment, node = snapshot.values_at('comment', 'node')
    return nil unless comment.is_a?(Hash) && node.is_a?(Hash)
    api_base = "https://api.github.com/repos/#{repo}/issues"
    return nil unless comment['id'] == comment_id &&
      comment['url'] == "#{api_base}/comments/#{comment_id}" &&
      comment['issue_url'] == "#{api_base}/#{issue_number}" &&
      comment['html_url'] == "https://github.com/#{repo}/issues/#{issue_number}#issuecomment-#{comment_id}"
    user = comment['user']
    return nil unless user.is_a?(Hash) && user['id'] == approver_id && user['type'] == 'User'
    return nil unless node['id'] == comment['node_id'] && node.key?('lastEditedAt') && node['lastEditedAt'].nil?
    return nil unless comment['created_at'].is_a?(String) && comment['created_at'] == comment['updated_at']
    fields = parse_body(comment['body'])
    return nil unless fields && fields['task_digest'] == AutomationDecision.task_digest(task) && fields['head'] == head
    created = Time.iso8601(comment['created_at'])
    expires = Time.iso8601(fields['expires_at'])
    return nil unless created.utc.iso8601 == comment['created_at'] &&
      created <= now && now < expires && expires <= created + MAX_MINUTES * 60
    fields.merge('created_at' => comment['created_at'], 'source_ref' => comment['html_url'])
  rescue ArgumentError
    nil
  end

  def self.verify_and_prelaunch(input, client:, repo:, issue_number:, comment_id:, approver_id:,
                                reread: -> { input }, clock: -> { Time.now.utc })
    return stop('pilot task is not the exact read-only specification') unless pilot_task?(input[:task].data)
    return stop('GitHub approval source is not designated') unless repo == REPO &&
      issue_number.is_a?(Integer) && issue_number.positive? &&
      comment_id.is_a?(Integer) && comment_id.positive? &&
      approver_id.is_a?(Integer) && approver_id.positive? && client.is_a?(GitHubClient)

    snapshot = client.fetch_issue_comment(repo: repo, comment_id: comment_id)
    fields = verify_snapshot(snapshot, repo: repo, issue_number: issue_number, comment_id: comment_id,
                             approver_id: approver_id, task: input[:task].data, head: input[:git]['head'], now: clock.call)
    return stop('GitHub approval missing, edited, stale, or unauthorized') unless fields

    approval = { 'schema_version' => 1,
                 'approved_tasks' => [{ 'id' => PILOT_ID, 'sha256' => fields['task_digest'] }],
                 'max_tasks' => 1, 'tasks_completed' => 0, 'max_duration_minutes' => MAX_MINUTES,
                 'started_at' => fields['created_at'], 'expires_at' => fields['expires_at'],
                 'commit_allowed' => false, 'push_allowed' => false }
    approved = input.merge(approval: approval)
    receipt = { 'source_kind' => 'authenticated_user_approval', 'source_ref' => fields['source_ref'],
                'approval_digest' => AutomationDispatch.digest(approval),
                'binding_digest' => AutomationDispatch.digest(AutomationDispatch.approval_binding(approved)) }
    source_verifier = lambda do |candidate|
      fresh = client.fetch_issue_comment(repo: repo, comment_id: comment_id)
      current = verify_snapshot(fresh, repo: repo, issue_number: issue_number, comment_id: comment_id,
                                approver_id: approver_id, task: input[:task].data, head: input[:git]['head'], now: clock.call)
      current == fields && candidate == receipt
    end
    current_input = -> { reread.call.merge(approval: approval) }
    result = AutomationDispatch.prelaunch(approved, receipt: receipt, source_verifier: source_verifier,
                                          reread: current_input, clock: clock)
    result['dispatch_envelope']['read_only'] = true if result['status'] == 'PRELAUNCH_READY'
    result.merge('approval_status' => result['status'] == 'PRELAUNCH_READY' ? 'APPROVAL_VERIFIED' : 'STOP: HOLD',
                 'read_only' => result['status'] == 'PRELAUNCH_READY')
  rescue AutomationDecision::Invalid, SystemCallError => e
    stop(e.message)
  end

  class FixtureClient < GitHubClient
    def initialize(snapshot)
      @snapshots = snapshot.is_a?(Array) ? snapshot : [snapshot]
      @reads = 0
    end

    def fetch_issue_comment(repo:, comment_id:)
      snapshot = @snapshots[[@reads, @snapshots.length - 1].min]
      @reads += 1
      Marshal.load(Marshal.dump(snapshot))
    end
  end

  def self.self_test
    live = AutomationDispatch.read_live
    head = 'a' * 40
    now = Time.utc(2026, 9, 28, 0, 0, 0)
    task = AutomationDecision.fixture(live[:task].data.merge(
      'state' => 'COMPLETE', 'risk_lane' => 'GREEN', 'auto_start_allowed' => true,
      'task_id' => PILOT_ID, 'title' => PILOT_TITLE, 'goal' => PILOT_GOAL,
      'allowed_files' => PILOT_FILES, 'forbidden_files' => PILOT_FORBIDDEN,
      'validation_required' => PILOT_VALIDATION, 'stop_conditions' => PILOT_STOP
    ), live[:task].body)
    handoff = AutomationDecision.fixture(live[:handoff].data.merge(
      'state' => 'COMPLETE', 'risk_lane' => 'GREEN', 'auto_start_allowed' => true,
      'validation' => { 'complete' => true, 'passing' => true, 'head' => head, 'evidence' => 'synthetic docs check' }
    ), live[:handoff].body)
    git = { 'branch' => 'main', 'head' => head, 'remote_head' => head, 'entries' => [] }
    green = live.merge(task: task, handoff: handoff, git: git)
    comment_id = 123
    issue_number = 7
    approver_id = 42
    created_at = (now - 60).iso8601
    expires_at = (now + 600).iso8601
    body = approval_text(task_digest: AutomationDecision.task_digest(task.data), head: head, expires_at: expires_at)
    api_base = "https://api.github.com/repos/#{REPO}/issues"
    comment = { 'id' => comment_id, 'node_id' => 'synthetic-node',
                'url' => "#{api_base}/comments/#{comment_id}", 'issue_url' => "#{api_base}/#{issue_number}",
                'html_url' => "https://github.com/#{REPO}/issues/#{issue_number}#issuecomment-#{comment_id}",
                'body' => body, 'user' => { 'id' => approver_id, 'type' => 'User' },
                'created_at' => created_at, 'updated_at' => created_at }
    snapshot = { 'comment' => comment, 'node' => { 'id' => 'synthetic-node', 'lastEditedAt' => nil } }
    cases = {
      'valid_author_and_approval' => [snapshot, green, approver_id, 'PRELAUNCH_READY'],
      'wrong_author' => [snapshot.merge('comment' => comment.merge('user' => { 'id' => 43, 'type' => 'User' })), green, approver_id, 'STOP: HOLD'],
      'stale_head' => [snapshot, green.merge(git: git.merge('head' => 'b' * 40)), approver_id, 'STOP: HOLD'],
      'stale_digest' => [snapshot.merge('comment' => comment.merge('body' => approval_text(task_digest: 'b' * 64, head: head, expires_at: expires_at))), green, approver_id, 'STOP: HOLD'],
      'expired_approval' => [snapshot.merge('comment' => comment.merge('body' => approval_text(task_digest: AutomationDecision.task_digest(task.data), head: head, expires_at: (now - 1).iso8601))), green, approver_id, 'STOP: HOLD'],
      'edited_approval' => [snapshot.merge('node' => { 'id' => 'synthetic-node', 'lastEditedAt' => now.iso8601 }), green, approver_id, 'STOP: HOLD'],
      'rest_edit_timestamp' => [snapshot.merge('comment' => comment.merge('updated_at' => now.iso8601)), green, approver_id, 'STOP: HOLD'],
      'edited_after_first_fetch' => [[snapshot, snapshot.merge('node' => { 'id' => 'synthetic-node', 'lastEditedAt' => now.iso8601 })], green, approver_id, 'STOP: HOLD'],
      'missing_approval' => [nil, green, approver_id, 'STOP: HOLD'],
      'commit_push_mismatch' => [snapshot.merge('comment' => comment.merge('body' => body.sub('push_allowed: false', 'push_allowed: true'))), green, approver_id, 'STOP: HOLD'],
      'ambiguous_text' => [snapshot.merge('comment' => comment.merge('body' => "#{body}\nextra: yes")), green, approver_id, 'STOP: HOLD'],
      'live_hold' => [snapshot, live, approver_id, 'STOP: HOLD']
    }
    failures = 0
    cases.each do |name, (evidence, candidate, designated_id, expected)|
      result = verify_and_prelaunch(candidate, client: FixtureClient.new(evidence), repo: REPO,
                                    issue_number: issue_number, comment_id: comment_id, approver_id: designated_id,
                                    reread: -> { candidate }, clock: -> { now })
      good = result['status'] == expected && result['dispatched'] == false &&
        (expected == 'PRELAUNCH_READY' ? result['approval_status'] == 'APPROVAL_VERIFIED' &&
          result['dispatch_envelope']['task_id'] == PILOT_ID &&
          result['dispatch_envelope']['read_only'] == true && result['read_only'] == true :
          result['dispatch_envelope'].nil?)
      failures += 1 unless good
      puts JSON.generate({ 'case' => name }.merge(result))
    end
    puts "github_approval_self_test=#{failures.zero? ? 'PASS' : 'FAIL'} cases=#{cases.length} failures=#{failures} dispatched=0"
    exit(failures.zero? ? 0 : 1)
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV == ['--self-test']
    AutomationGitHubApproval.self_test
  else
    puts JSON.pretty_generate(AutomationGitHubApproval.stop('no designated approver or issue comment configured; live HOLD'))
  end
end
