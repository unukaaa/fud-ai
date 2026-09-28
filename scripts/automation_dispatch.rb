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

  def self.working_tree_state(git, root: ROOT)
    git.fetch('entries').map do |status, path|
      full_path = File.expand_path(path, root)
      raise AutomationDecision::Invalid, 'Git path escapes repository' unless full_path.start_with?("#{root}/")
      fingerprint = if File.symlink?(full_path)
        digest(File.readlink(full_path))
      elsif File.file?(full_path)
        Digest::SHA256.file(full_path).hexdigest
      else
        'missing-or-nonregular'
      end
      [status, path, fingerprint]
    end
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
      'protected_file_state' => digest(working_tree_state(git))
    }
  end

  def self.stop(reasons)
    { 'status' => 'STOP: HOLD', 'reasons' => reasons, 'dispatch_envelope' => nil, 'dispatched' => false }
  end

  # A receipt is supplied by an authenticated controller, never read from repo files.
  # This comparison binds its external approval to the exact proposed invocation;
  # it cannot authenticate the controller itself and never launches a task.
  def self.approval_binding(input)
    task = input[:task].data
    approval = input[:approval]
    {
      'task_id' => task['task_id'],
      'task_digest' => AutomationDecision.task_digest(task),
      'head' => input[:git]['head'],
      'working_tree_digest' => digest(working_tree_state(input[:git])),
      'allowed_files' => task['allowed_files'],
      'forbidden_files' => task['forbidden_files'],
      'validation_evidence' => input[:handoff].data['validation'],
      'bounds' => approval.slice('max_tasks', 'tasks_completed', 'max_duration_minutes', 'started_at', 'expires_at'),
      'expires_at' => approval['expires_at'],
      'commit_allowed' => task['commit_allowed'],
      'push_allowed' => task['push_allowed'],
      'approval_commit_allowed' => approval['commit_allowed'],
      'approval_push_allowed' => approval['push_allowed']
    }
  end

  def self.source_verified?(source_verifier, receipt)
    source_verifier.respond_to?(:call) && source_verifier.call(receipt) == true
  rescue StandardError
    false
  end

  def self.receipt_reason(receipt, input, source_verifier:)
    return 'missing trusted approval provenance' unless receipt.is_a?(Hash)
    required = %w[source_kind source_ref approval_digest binding_digest]
    return 'invalid trusted approval provenance' unless receipt.keys.sort == required.sort &&
      receipt['source_kind'] == 'authenticated_user_approval' &&
      receipt['source_ref'].is_a?(String) && !receipt['source_ref'].strip.empty? &&
      %w[approval_digest binding_digest].all? { |key| receipt[key].is_a?(String) && receipt[key].match?(/\A[0-9a-f]{64}\z/) }
    return 'approval source not independently verified' unless source_verified?(source_verifier, receipt)
    return 'approval changed or is not authorized by source' unless receipt['approval_digest'] == digest(input[:approval])
    return 'approved task binding changed' unless receipt['binding_digest'] == digest(approval_binding(input))
    nil
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
  rescue AutomationDecision::Invalid, SystemCallError => e
    stop([e.message])
  end

  def self.prelaunch(input, receipt:, source_verifier: nil, reread: -> { input }, clock: -> { Time.now.utc })
    initial = dry_run(input, reread: reread, now: clock.call)
    return stop(initial['reasons']) unless initial['status'] == 'DRY_RUN_DISPATCH_READY'

    reason = receipt_reason(receipt, input, source_verifier: source_verifier)
    return stop([reason]) if reason

    # This is the final read-only gate. A future launcher must keep it adjacent
    # to dispatch and obtain the receipt from a genuinely trusted source.
    current = reread.call
    before = stable_fields(input)
    after = stable_fields(current)
    changed = before.keys.select { |key| before[key] != after[key] }
    return stop(["inputs changed before launch: #{changed.join(', ')}"]) unless changed.empty?

    final = AutomationDecision.decide(current[:policy], current[:handoff], current[:task],
                                      approval: current[:approval], git: current[:git], now: clock.call)
    return stop(final['reasons']) unless final['decision'] == 'LAUNCH_ALLOWED'
    reason = receipt_reason(receipt, current, source_verifier: source_verifier)
    return stop([reason]) if reason

    { 'status' => 'PRELAUNCH_READY', 'reasons' => [],
      'dispatch_envelope' => initial['dispatch_envelope'].merge('approval_source_ref' => receipt['source_ref'],
                                                               'approval_binding_digest' => receipt['binding_digest']),
      'dispatched' => false }
  rescue AutomationDecision::Invalid, SystemCallError => e
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

  def self.prelaunch_self_test
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
    receipt = { 'source_kind' => 'authenticated_user_approval', 'source_ref' => 'synthetic-approved-plan',
                'approval_digest' => digest(approval), 'binding_digest' => digest(approval_binding(green)) }
    verifier = ->(candidate) { candidate == receipt }
    changed_task = ->(fields) { green.merge(task: AutomationDecision::Doc.new(task.data.merge(fields), task.body)) }
    changed_handoff = ->(fields) { green.merge(handoff: AutomationDecision::Doc.new(handoff.data.merge(fields), handoff.body)) }
    cases = {
      'live_hold' => [live, nil, nil, 'STOP: HOLD'],
      'valid_green' => [green, receipt, nil, 'PRELAUNCH_READY'],
      'approval_expired' => [green.merge(approval: approval.merge('expires_at' => (now - 1).iso8601)), receipt, nil, 'STOP: HOLD'],
      'approval_bounds_changed' => [green, receipt, green.merge(approval: approval.merge('tasks_completed' => 1)), 'STOP: HOLD'],
      'approval_permission_changed' => [green, receipt, green.merge(approval: approval.merge('commit_allowed' => true)), 'STOP: HOLD'],
      'head_changed' => [green, receipt, green.merge(git: git.merge('head' => 'b' * 40)), 'STOP: HOLD'],
      'validation_stale' => [green, receipt, changed_handoff.call('validation' => handoff.data['validation'].merge('head' => 'b' * 40)), 'STOP: HOLD'],
      'allowed_files_changed' => [green, receipt, changed_task.call('allowed_files' => ['CURRENT_HANDOFF.md']), 'STOP: HOLD'],
      'forbidden_files_changed' => [green, receipt, changed_task.call('forbidden_files' => task.data['forbidden_files'] + ['local-models/**']), 'STOP: HOLD'],
      'task_digest_changed' => [green, receipt, changed_task.call('goal' => 'Changed task goal'), 'STOP: HOLD'],
      'permission_changed' => [green, receipt, changed_task.call('commit_allowed' => true), 'STOP: HOLD'],
      'human_decision_required' => [green, receipt, changed_handoff.call('human_decision_required' => true), 'STOP: HOLD'],
      'protected_file_state_changed' => [green, receipt, green.merge(git: git.merge('entries' => [[' M', AutomationDecision::PROTECTED.first]])), 'STOP: HOLD'],
      'missing_trusted_provenance' => [green, nil, nil, 'STOP: HOLD'],
      'unverified_source' => [green, receipt, nil, 'STOP: HOLD'],
      'approval_source_changed' => [green, receipt.merge('binding_digest' => 'b' * 64), nil, 'STOP: HOLD']
    }
    failures = 0
    cases.each do |name, (initial, trusted, changed, expected)|
      result = prelaunch(initial, receipt: trusted, source_verifier: name == 'unverified_source' ? nil : verifier,
                         reread: -> { changed || initial }, clock: -> { now })
      envelope = result['dispatch_envelope']
      valid_envelope = expected == 'PRELAUNCH_READY' ?
        envelope && envelope['task_id'] == 'safe-doc-audit' && envelope['head'] == head &&
          envelope['allowed_files'] == task.data['allowed_files'] &&
          envelope['forbidden_files'] == task.data['forbidden_files'] &&
          envelope['validation_evidence'] == handoff.data['validation'] &&
          envelope['task_digest'] == AutomationDecision.task_digest(task.data) &&
          envelope['approval_digest'] == digest(approval) &&
          envelope['bounds'] == approval.slice('max_tasks', 'tasks_completed', 'max_duration_minutes', 'started_at', 'expires_at') &&
          envelope['approval_source_ref'] == receipt['source_ref'] &&
          envelope['approval_binding_digest'] == receipt['binding_digest'] &&
          !envelope['commit_allowed'] && !envelope['push_allowed'] :
        envelope.nil?
      failures += 1 unless result['status'] == expected && result['dispatched'] == false && valid_envelope
      puts JSON.generate({ 'case' => name }.merge(result))
    end
    clock_calls = 0
    expiry_clock = -> { clock_calls += 1; clock_calls == 1 ? now : now + 601 }
    expired_during_recheck = prelaunch(green, receipt: receipt, source_verifier: verifier,
                                       reread: -> { green }, clock: expiry_clock)
    failures += 1 unless expired_during_recheck['status'] == 'STOP: HOLD' &&
      expired_during_recheck['dispatch_envelope'].nil? && expired_during_recheck['dispatched'] == false
    puts JSON.generate({ 'case' => 'expired_during_final_recheck' }.merge(expired_during_recheck))
    require 'tmpdir'
    Dir.mktmpdir('foodai-prelaunch-fixture-') do |root|
      path = File.join(root, 'protected.txt')
      File.write(path, 'before')
      git_state = { 'entries' => [[' M', 'protected.txt']] }
      before = digest(working_tree_state(git_state, root: root))
      File.write(path, 'after')
      after = digest(working_tree_state(git_state, root: root))
      unchanged = before == after
      failures += 1 if unchanged
      puts JSON.generate('case' => 'same_status_content_changed', 'detected' => !unchanged, 'dispatched' => false)
    end
    puts "prelaunch_self_test=#{failures.zero? ? 'PASS' : 'FAIL'} cases=#{cases.length + 2} failures=#{failures} dispatched=0"
    exit(failures.zero? ? 0 : 1)
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV == ['--self-test']
    AutomationDispatch.self_test
  elsif ARGV == ['--prelaunch-self-test']
    AutomationDispatch.prelaunch_self_test
  elsif ARGV == ['--prelaunch']
    begin
      input = AutomationDispatch.read_live
      output = AutomationDispatch.prelaunch(input, receipt: nil, reread: -> { AutomationDispatch.read_live })
    rescue AutomationDecision::Invalid, SystemCallError => e
      output = AutomationDispatch.stop([e.message])
    end
    puts output['status']
    puts JSON.pretty_generate(output)
  elsif ARGV.empty? || (ARGV.length == 2 && ARGV.first == '--approval')
    begin
      approval_path = ARGV.empty? ? nil : ARGV.last
      input = AutomationDispatch.read_live(approval_path)
      output = AutomationDispatch.dry_run(input, reread: -> { AutomationDispatch.read_live(approval_path) })
    rescue AutomationDecision::Invalid, SystemCallError => e
      output = AutomationDispatch.stop([e.message])
    end
    puts output['status']
    puts JSON.pretty_generate(output)
  else
    warn 'Usage: ruby scripts/automation_dispatch.rb [--self-test | --prelaunch-self-test | --prelaunch | --approval TRUSTED_PLAN.yml]'
    exit 2
  end
end
