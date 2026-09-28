#!/usr/bin/env ruby
# Dry-run adapter only. No task-launch, network, or repository-write capability.
require_relative 'automation_decision'

module AutomationDispatch
  ROOT = AutomationDecision::ROOT

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(AutomationDecision.canonical(value)))
  end

  def self.read_live(approval_path = nil)
    names = %w[AUTOMATION_POLICY.md CURRENT_HANDOFF.md NEXT_TASK.md]
    docs = names.map { |name| AutomationDecision.front_matter(File.read(File.join(ROOT, name)), name) }
    {
      policy: docs[0], handoff: docs[1], task: docs[2],
      approval: approval_path ? AutomationDecision.read_approval(approval_path) : nil,
      git: AutomationDecision.live_git
    }
  end

  def self.stable_fields(input)
    handoff = input[:handoff]
    task = input[:task]
    git = input[:git]
    {
      'policy' => digest([input[:policy].data, input[:policy].body]),
      'handoff' => digest([handoff.data, handoff.body]),
      'task_digest' => AutomationDecision.task_digest(task.data),
      'task_body' => digest(task.body),
      'approval_digest' => input[:approval] && digest(input[:approval]),
      'validation_evidence' => digest(handoff.data['validation']),
      'HEAD' => git['head'],
      'origin_main' => git['remote_head'],
      'branch' => git['branch'],
      'protected_file_state' => digest(git['entries'])
    }
  end

  def self.stop(reasons)
    { 'status' => 'STOP: HOLD', 'reasons' => reasons, 'dispatch_envelope' => nil, 'dispatched' => false }
  end

  def self.dry_run(input, reread: -> { input }, now: Time.now.utc)
    first = AutomationDecision.decide(input[:policy], input[:handoff], input[:task], approval: input[:approval], git: input[:git], now: now)
    return stop(first['reasons']) unless first['decision'] == 'LAUNCH_ALLOWED'

    current = reread.call
    before = stable_fields(input)
    after = stable_fields(current)
    changed = before.keys.select { |key| before[key] != after[key] }
    return stop(["inputs changed after gate: #{changed.join(', ')}"]) unless changed.empty?

    second = AutomationDecision.decide(current[:policy], current[:handoff], current[:task], approval: current[:approval], git: current[:git], now: now)
    return stop(second['reasons']) unless second['decision'] == 'LAUNCH_ALLOWED'

    task = current[:task].data
    handoff = current[:handoff].data
    approval = current[:approval]
    envelope = {
      'task_id' => task['task_id'],
      'title' => task['title'],
      'goal' => task['goal'],
      'head' => current[:git]['head'],
      'allowed_files' => task['allowed_files'],
      'forbidden_files' => task['forbidden_files'],
      'validation_required' => task['validation_required'],
      'validation_evidence' => handoff['validation'],
      'stop_conditions' => task['stop_conditions'],
      'bounds' => approval.slice('max_tasks', 'tasks_completed', 'max_duration_minutes', 'started_at', 'expires_at'),
      'task_digest' => AutomationDecision.task_digest(task),
      'approval_digest' => digest(approval),
      'commit_allowed' => task['commit_allowed'],
      'push_allowed' => task['push_allowed']
    }
    { 'status' => 'DRY_RUN_DISPATCH_READY', 'reasons' => [], 'dispatch_envelope' => envelope, 'dispatched' => false }
  rescue AutomationDecision::Invalid, Errno::ENOENT => e
    stop([e.message])
  end

  def self.self_test
    live = read_live
    head = 'a' * 40
    now = Time.utc(2026, 9, 28, 0, 0, 0)
    handoff = AutomationDecision.fixture(live[:handoff].data.merge(
      'state' => 'COMPLETE', 'risk_lane' => 'GREEN', 'auto_start_allowed' => true,
      'validation' => { 'complete' => true, 'passing' => true, 'head' => head, 'evidence' => 'synthetic exit-zero checks' }
    ), live[:handoff].body)
    task = AutomationDecision.fixture(live[:task].data.merge(
      'state' => 'COMPLETE', 'risk_lane' => 'GREEN', 'auto_start_allowed' => true,
      'task_id' => 'safe-doc-audit', 'title' => 'Check routing documentation links',
      'goal' => 'Read routing documentation and report broken local links.',
      'validation_required' => ['Record checked links and an exit-zero result.']
    ), live[:task].body)
    approval = {
      'schema_version' => 1,
      'approved_tasks' => [{ 'id' => task.data['task_id'], 'sha256' => AutomationDecision.task_digest(task.data) }],
      'max_tasks' => 1, 'tasks_completed' => 0, 'max_duration_minutes' => 15,
      'started_at' => (now - 60).iso8601, 'expires_at' => (now + 600).iso8601,
      'commit_allowed' => false, 'push_allowed' => false
    }
    git = { 'branch' => 'main', 'head' => head, 'remote_head' => head, 'entries' => [] }
    green = { policy: live[:policy], handoff: handoff, task: task, approval: approval, git: git }
    cases = {
      'live_hold' => [live, nil, 'STOP: HOLD'],
      'valid_green' => [green, nil, 'DRY_RUN_DISPATCH_READY'],
      'stale_head' => [green, green.merge(git: git.merge('head' => 'b' * 40)), 'STOP: HOLD'],
      'changed_task_digest' => [green, green.merge(task: AutomationDecision::Doc.new(task.data.merge('goal' => 'Changed goal'), task.body)), 'STOP: HOLD'],
      'changed_approval' => [green, green.merge(approval: approval.merge('tasks_completed' => 1)), 'STOP: HOLD'],
      'changed_validation_evidence' => [green, green.merge(handoff: AutomationDecision::Doc.new(handoff.data.merge('validation' => handoff.data['validation'].merge('evidence' => 'changed')), handoff.body)), 'STOP: HOLD'],
      'changed_protected_state' => [green, green.merge(git: git.merge('entries' => [['M ', AutomationDecision::PROTECTED.first]])), 'STOP: HOLD'],
      'expired_approval' => [green.merge(approval: approval.merge('expires_at' => (now - 1).iso8601)), nil, 'STOP: HOLD'],
      'missing_approval' => [green.merge(approval: nil), nil, 'STOP: HOLD'],
      'protected_file_conflict' => [green.merge(git: git.merge('entries' => [['M ', AutomationDecision::PROTECTED.first]])), nil, 'STOP: HOLD'],
      'incomplete_validation' => [green.merge(handoff: AutomationDecision::Doc.new(handoff.data.merge('validation' => handoff.data['validation'].merge('complete' => false)), handoff.body)), nil, 'STOP: HOLD']
    }
    failures = 0
    cases.each do |name, (initial, changed, expected)|
      result = dry_run(initial, reread: -> { changed || initial }, now: now)
      failures += 1 unless result['status'] == expected && result['dispatched'] == false && (expected == 'DRY_RUN_DISPATCH_READY') == !result['dispatch_envelope'].nil?
      puts JSON.generate({ 'case' => name }.merge(result))
    end
    puts "dispatcher_self_test=#{failures.zero? ? 'PASS' : 'FAIL'} cases=#{cases.length} failures=#{failures} dispatched=0"
    exit(failures.zero? ? 0 : 1)
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV == ['--self-test']
    AutomationDispatch.self_test
  elsif ARGV.empty? || (ARGV.length == 2 && ARGV.first == '--approval')
    begin
      approval_path = ARGV.empty? ? nil : ARGV.last
      input = AutomationDispatch.read_live(approval_path)
      output = AutomationDispatch.dry_run(input, reread: -> { AutomationDispatch.read_live(approval_path) })
    rescue AutomationDecision::Invalid, Errno::ENOENT => e
      output = AutomationDispatch.stop([e.message])
    end
    puts output['status']
    puts JSON.pretty_generate(output)
  else
    warn 'Usage: ruby scripts/automation_dispatch.rb [--self-test | --approval TRUSTED_PLAN.yml]'
    exit 2
  end
end
