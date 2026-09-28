#!/usr/bin/env ruby
# Dry-run adapter only. No task-launch, network, or repository-write capability.
require_relative 'automation_decision'

module AutomationDispatch
  ROOT = AutomationDecision::ROOT

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(AutomationDecision.canonical(value)))
  end

  def self.read_live
    names = %w[AUTOMATION_POLICY.md CURRENT_HANDOFF.md NEXT_TASK.md]
    docs = names.map { |name| AutomationDecision.front_matter(File.read(File.join(ROOT, name)), name) }
    {
      policy: docs[0], handoff: docs[1], task: docs[2],
      approval: nil,
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
      'validation_receipt_digest' => input[:validation_receipt] && digest(input[:validation_receipt]),
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
      'validation_receipt_digest' => digest(input[:validation_receipt]),
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

  def self.validation_reason(receipt, input, verifier:, now:)
    return 'missing trusted external validation receipt' unless receipt.is_a?(Hash)
    required = %w[schema_version source_kind source_ref head task_id task_digest results working_tree_digest max_tasks tasks_completed max_duration_minutes validated_at expires_at]
    return 'invalid external validation receipt' unless receipt.keys.sort == required.sort &&
      receipt['schema_version'] == 1 && receipt['source_kind'] == 'trusted_controller_validation' &&
      receipt['source_ref'].is_a?(String) && !receipt['source_ref'].strip.empty? &&
      receipt['results'].is_a?(Hash) && receipt['results'].keys.sort == %w[complete evidence passing] &&
      receipt['results']['complete'] == true && receipt['results']['passing'] == true &&
      receipt['results']['evidence'].is_a?(String) && !receipt['results']['evidence'].strip.empty? &&
      receipt['max_tasks'].is_a?(Integer) && receipt['max_tasks'].positive? &&
      receipt['tasks_completed'].is_a?(Integer) && receipt['tasks_completed'] >= 0 &&
      receipt['max_duration_minutes'].is_a?(Integer) && receipt['max_duration_minutes'].positive?
    return 'validation source not independently verified' unless source_verified?(verifier, receipt)
    task = input[:task].data
    git = input[:git]
    return 'validation receipt binding changed' unless receipt['head'] == git['head'] &&
      receipt['task_id'] == task['task_id'] && receipt['task_digest'] == AutomationDecision.task_digest(task) &&
      receipt['working_tree_digest'] == digest(working_tree_state(git))
    approval = input[:approval]
    return 'validation bounds differ from human approval' unless approval.is_a?(Hash) &&
      %w[max_tasks tasks_completed max_duration_minutes].all? { |key| receipt[key] == approval[key] }
    validated = Time.iso8601(receipt['validated_at'])
    expires = Time.iso8601(receipt['expires_at'])
    return 'external validation receipt expired or malformed' unless validated.utc.iso8601 == receipt['validated_at'] &&
      expires.utc.iso8601 == receipt['expires_at'] && validated <= now && now < expires &&
      expires <= validated + receipt['max_duration_minutes'] * 60
    nil
  rescue ArgumentError, TypeError
    'external validation receipt expired or malformed'
  end

  def self.approval_reason(input, now:)
    approval = input[:approval]
    return 'missing authenticated human approval' unless approval.is_a?(Hash)
    AutomationDecision.approval!(approval)
    task = input[:task].data
    return 'task not exactly authorized' unless approval['approved_tasks'].length == 1 &&
      approval['approved_tasks'][0] == { 'id' => task['task_id'], 'sha256' => AutomationDecision.task_digest(task) }
    return 'approval exceeds task bounds' if (task['max_tasks'] && approval['max_tasks'] != task['max_tasks']) ||
      (task['max_duration_minutes'] && approval['max_duration_minutes'] != task['max_duration_minutes'])
    return 'task bound exhausted' unless approval['tasks_completed'] < approval['max_tasks']
    started = Time.iso8601(approval['started_at'])
    expires = Time.iso8601(approval['expires_at'])
    return 'stale or expired human approval' unless started.utc.iso8601 == approval['started_at'] &&
      expires.utc.iso8601 == approval['expires_at'] && started <= now && now < expires &&
      expires <= started + approval['max_duration_minutes'] * 60
    nil
  rescue ArgumentError, TypeError
    'stale or expired human approval'
  end

  # A trusted controller must inject this callback; it is never inferred from
  # the local origin/main ref, which may be stale.
  def self.remote_main_head
    output, status = Open3.capture2e('git', '-C', ROOT, 'ls-remote', 'origin', 'refs/heads/main')
    raise AutomationDecision::Invalid, 'fresh remote HEAD unavailable' unless status.success?
    match = output.match(/\A([0-9a-f]{40})\s+refs\/heads\/main\s*\z/)
    raise AutomationDecision::Invalid, 'fresh remote HEAD malformed' unless match
    match[1]
  end

  def self.dry_run(input, reread: -> { input }, now: Time.now.utc)
    first = AutomationDecision.decide(input[:policy], input[:handoff], input[:task], git: input[:git], now: now)
    return stop(first['reasons']) unless first['decision'] == 'READY_FOR_APPROVAL'

    current = reread.call
    before = stable_fields(input.merge(approval: nil, validation_receipt: nil))
    after = stable_fields(current.merge(approval: nil, validation_receipt: nil))
    changed = before.keys.select { |key| before[key] != after[key] }
    return stop(["inputs changed after gate: #{changed.join(', ')}"]) unless changed.empty?

    second = AutomationDecision.decide(current[:policy], current[:handoff], current[:task], git: current[:git], now: now)
    return stop(second['reasons']) unless second['decision'] == 'READY_FOR_APPROVAL'
    { 'status' => 'READY_FOR_APPROVAL', 'reasons' => [], 'dispatch_envelope' => nil,
      'task_id' => current[:task].data['task_id'],
      'task_digest' => AutomationDecision.task_digest(current[:task].data), 'dispatched' => false }
  rescue AutomationDecision::Invalid, SystemCallError => e
    stop([e.message])
  rescue StandardError
    stop(['repository routing recheck failed'])
  end

  def self.prelaunch(input, receipt:, source_verifier: nil, validation_receipt: nil,
                     validation_verifier: nil, reread: -> { input }, clock: -> { Time.now.utc },
                     remote_head_reader: -> { remote_main_head })
    initial = dry_run(input, reread: reread, now: clock.call)
    return stop(initial['reasons']) unless initial['status'] == 'READY_FOR_APPROVAL'

    current_time = clock.call
    reason = approval_reason(input, now: current_time)
    return stop([reason]) if reason
    reason = validation_reason(validation_receipt, input, verifier: validation_verifier, now: current_time)
    return stop([reason]) if reason
    reason = receipt_reason(receipt, input.merge(validation_receipt: validation_receipt), source_verifier: source_verifier)
    return stop([reason]) if reason

    # This is the final read-only gate. A future launcher must keep it adjacent
    # to dispatch and obtain the receipt from a genuinely trusted source.
    current = reread.call
    before = stable_fields(input.merge(validation_receipt: validation_receipt))
    after = stable_fields(current.merge(validation_receipt: validation_receipt))
    changed = before.keys.select { |key| before[key] != after[key] }
    return stop(["inputs changed before launch: #{changed.join(', ')}"]) unless changed.empty?

    final = AutomationDecision.decide(current[:policy], current[:handoff], current[:task], git: current[:git], now: clock.call)
    return stop(final['reasons']) unless final['decision'] == 'READY_FOR_APPROVAL'
    current_time = clock.call
    reason = approval_reason(current, now: current_time)
    return stop([reason]) if reason
    reason = validation_reason(validation_receipt, current, verifier: validation_verifier, now: current_time)
    return stop([reason]) if reason
    reason = receipt_reason(receipt, current.merge(validation_receipt: validation_receipt), source_verifier: source_verifier)
    return stop([reason]) if reason
    fresh_head = remote_head_reader.call
    return stop(['fresh remote HEAD differs from approved HEAD']) unless fresh_head == current[:git]['head']
    task = current[:task].data
    approval = current[:approval]
    envelope = {
      'task_id' => task['task_id'], 'title' => task['title'], 'goal' => task['goal'],
      'head' => fresh_head, 'allowed_files' => task['allowed_files'],
      'forbidden_files' => task['forbidden_files'], 'validation_required' => task['validation_required'],
      'validation_results' => validation_receipt['results'], 'stop_conditions' => task['stop_conditions'],
      'bounds' => approval.slice('max_tasks', 'tasks_completed', 'max_duration_minutes', 'started_at', 'expires_at'),
      'task_digest' => AutomationDecision.task_digest(task),
      'approval_digest' => digest(approval), 'validation_receipt_digest' => digest(validation_receipt),
      'commit_allowed' => task['commit_allowed'], 'push_allowed' => task['push_allowed'],
      'read_only' => task['read_only'] == true,
      'approval_source_ref' => receipt['source_ref'], 'approval_binding_digest' => receipt['binding_digest'],
      'validation_source_ref' => validation_receipt['source_ref']
    }
    { 'status' => 'PRELAUNCH_READY', 'reasons' => [],
      'dispatch_envelope' => envelope,
      'dispatched' => false }
  rescue AutomationDecision::Invalid, SystemCallError => e
    stop([e.message])
  rescue StandardError
    stop(['pre-launch recheck failed'])
  end

  def self.self_test
    live = read_live
    head = 'a' * 40
    now = Time.utc(2026, 9, 28, 0, 0, 0)
    handoff = AutomationDecision.fixture(live[:handoff].data.merge(
      'state' => 'COMPLETE', 'risk_lane' => 'GREEN', 'auto_start_allowed' => true
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
    hold = green.merge(
      handoff: AutomationDecision.fixture(handoff.data.merge('state' => 'HOLD', 'risk_lane' => 'AMBER', 'auto_start_allowed' => false), handoff.body),
      task: AutomationDecision.fixture(task.data.merge('state' => 'HOLD', 'risk_lane' => 'AMBER', 'auto_start_allowed' => false), task.body)
    )
    cases = {
      'synthetic_hold' => [hold, nil, 'STOP: HOLD'],
      'valid_green' => [green, nil, 'READY_FOR_APPROVAL'],
      'stale_head' => [green, green.merge(git: git.merge('head' => 'b' * 40)), 'STOP: HOLD'],
      'changed_task_digest' => [green, green.merge(task: AutomationDecision::Doc.new(task.data.merge('goal' => 'Changed goal'), task.body)), 'STOP: HOLD'],
      'changed_approval' => [green, green.merge(approval: approval.merge('tasks_completed' => 1)), 'READY_FOR_APPROVAL'],
      'changed_handoff_body' => [green, green.merge(handoff: AutomationDecision::Doc.new(handoff.data, "#{handoff.body}\nchanged")), 'STOP: HOLD'],
      'changed_protected_state' => [green, green.merge(git: git.merge('entries' => [['M ', AutomationDecision::PROTECTED.first]])), 'STOP: HOLD'],
      'expired_approval' => [green.merge(approval: approval.merge('expires_at' => (now - 1).iso8601)), nil, 'READY_FOR_APPROVAL'],
      'missing_approval' => [green.merge(approval: nil), nil, 'READY_FOR_APPROVAL'],
      'protected_file_conflict' => [green.merge(git: git.merge('entries' => [['M ', AutomationDecision::PROTECTED.first]])), nil, 'STOP: HOLD'],
      'embedded_validation_rejected' => [green.merge(handoff: AutomationDecision::Doc.new(handoff.data.merge('validation' => { 'head' => head }), handoff.body)), nil, 'STOP: HOLD']
    }
    failures = 0
    cases.each do |name, (initial, changed, expected)|
      result = dry_run(initial, reread: -> { changed || initial }, now: now)
      failures += 1 unless result['status'] == expected && result['dispatched'] == false &&
        result['dispatch_envelope'].nil? &&
        (expected == 'READY_FOR_APPROVAL' ? result['task_digest'] == AutomationDecision.task_digest(task.data) : true)
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
      'state' => 'COMPLETE', 'risk_lane' => 'GREEN', 'auto_start_allowed' => true
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
    validation = {
      'schema_version' => 1, 'source_kind' => 'trusted_controller_validation',
      'source_ref' => 'synthetic-controller-run', 'head' => head,
      'task_id' => task.data['task_id'], 'task_digest' => AutomationDecision.task_digest(task.data),
      'results' => { 'complete' => true, 'passing' => true, 'evidence' => 'synthetic exit-zero checks' },
      'working_tree_digest' => digest(working_tree_state(git)),
      'max_tasks' => 1, 'tasks_completed' => 0, 'max_duration_minutes' => 15,
      'validated_at' => (now - 60).iso8601, 'expires_at' => (now + 600).iso8601
    }
    receipt = { 'source_kind' => 'authenticated_user_approval', 'source_ref' => 'synthetic-approved-plan',
                'approval_digest' => digest(approval),
                'binding_digest' => digest(approval_binding(green.merge(validation_receipt: validation))) }
    verifier = ->(candidate) { candidate == receipt }
    validation_verifier = ->(candidate) { candidate == validation }
    changed_task = ->(fields) { green.merge(task: AutomationDecision::Doc.new(task.data.merge(fields), task.body)) }
    changed_handoff = ->(fields) { green.merge(handoff: AutomationDecision::Doc.new(handoff.data.merge(fields), handoff.body)) }
    cases = {
      'live_hold' => [live, nil, nil, nil, 'STOP: HOLD'],
      'valid_green' => [green, receipt, validation, nil, 'PRELAUNCH_READY'],
      'missing_validation_receipt' => [green, receipt, nil, nil, 'STOP: HOLD'],
      'stale_validation_head' => [green, receipt, validation.merge('head' => 'b' * 40), nil, 'STOP: HOLD'],
      'validation_worktree_mismatch' => [green, receipt, validation.merge('working_tree_digest' => 'b' * 64), nil, 'STOP: HOLD'],
      'validation_bounds_mismatch' => [green, receipt, validation.merge('max_tasks' => 2), nil, 'STOP: HOLD'],
      'incomplete_validation' => [green, receipt, validation.merge('results' => validation['results'].merge('complete' => false)), nil, 'STOP: HOLD'],
      'expired_validation' => [green, receipt, validation.merge('expires_at' => (now - 1).iso8601), nil, 'STOP: HOLD'],
      'approval_expired' => [green.merge(approval: approval.merge('expires_at' => (now - 1).iso8601)), receipt, validation, nil, 'STOP: HOLD'],
      'approval_bounds_changed' => [green, receipt, validation, green.merge(approval: approval.merge('tasks_completed' => 1)), 'STOP: HOLD'],
      'approval_permission_changed' => [green.merge(approval: approval.merge('commit_allowed' => true)), receipt, validation, nil, 'STOP: HOLD'],
      'head_changed' => [green, receipt, validation, green.merge(git: git.merge('head' => 'b' * 40)), 'STOP: HOLD'],
      'validation_stale' => [green, receipt, validation.merge('task_digest' => 'b' * 64), nil, 'STOP: HOLD'],
      'allowed_files_changed' => [green, receipt, validation, changed_task.call('allowed_files' => ['CURRENT_HANDOFF.md']), 'STOP: HOLD'],
      'forbidden_files_changed' => [green, receipt, validation, changed_task.call('forbidden_files' => task.data['forbidden_files'] + ['local-models/**']), 'STOP: HOLD'],
      'task_digest_changed' => [green, receipt, validation, changed_task.call('goal' => 'Changed task goal'), 'STOP: HOLD'],
      'permission_changed' => [green, receipt, validation, changed_task.call('commit_allowed' => true), 'STOP: HOLD'],
      'human_decision_required' => [green, receipt, validation, changed_handoff.call('human_decision_required' => true), 'STOP: HOLD'],
      'protected_file_state_changed' => [green, receipt, validation, green.merge(git: git.merge('entries' => [[' M', AutomationDecision::PROTECTED.first]])), 'STOP: HOLD'],
      'missing_trusted_provenance' => [green, nil, validation, nil, 'STOP: HOLD'],
      'valid_validation_no_approval' => [green.merge(approval: nil), nil, validation, nil, 'STOP: HOLD'],
      'unverified_source' => [green, receipt, validation, nil, 'STOP: HOLD'],
      'unverified_validation' => [green, receipt, validation, nil, 'STOP: HOLD'],
      'approval_source_changed' => [green, receipt.merge('binding_digest' => 'b' * 64), validation, nil, 'STOP: HOLD'],
      'fresh_remote_head_changed' => [green, receipt, validation, nil, 'STOP: HOLD'],
      'fresh_remote_head_unavailable' => [green, receipt, validation, nil, 'STOP: HOLD']
    }
    failures = 0
    cases.each do |name, (initial, trusted, evidence, changed, expected)|
      result = prelaunch(initial, receipt: trusted, source_verifier: name == 'unverified_source' ? nil : verifier,
                         validation_receipt: evidence,
                         validation_verifier: name == 'unverified_validation' ? nil : validation_verifier,
                         reread: -> { changed || initial }, clock: -> { now },
                         remote_head_reader: lambda {
                           raise AutomationDecision::Invalid, 'fresh remote HEAD unavailable' if name == 'fresh_remote_head_unavailable'
                           name == 'fresh_remote_head_changed' ? 'b' * 40 : head
                         })
      envelope = result['dispatch_envelope']
      valid_envelope = expected == 'PRELAUNCH_READY' ?
        envelope && envelope['task_id'] == 'safe-doc-audit' && envelope['head'] == head &&
          envelope['allowed_files'] == task.data['allowed_files'] &&
          envelope['forbidden_files'] == task.data['forbidden_files'] &&
          envelope['validation_results'] == validation['results'] &&
          envelope['validation_receipt_digest'] == digest(validation) &&
          envelope['task_digest'] == AutomationDecision.task_digest(task.data) &&
          envelope['approval_digest'] == digest(approval) &&
          envelope['bounds'] == approval.slice('max_tasks', 'tasks_completed', 'max_duration_minutes', 'started_at', 'expires_at') &&
          envelope['approval_source_ref'] == receipt['source_ref'] &&
          envelope['approval_binding_digest'] == receipt['binding_digest'] &&
          envelope['validation_source_ref'] == validation['source_ref'] &&
          !envelope['commit_allowed'] && !envelope['push_allowed'] :
        envelope.nil?
      failures += 1 unless result['status'] == expected && result['dispatched'] == false && valid_envelope
      puts JSON.generate({ 'case' => name }.merge(result))
    end
    clock_calls = 0
    expiry_clock = -> { clock_calls += 1; clock_calls == 1 ? now : now + 601 }
    expired_during_recheck = prelaunch(green, receipt: receipt, source_verifier: verifier,
                                       validation_receipt: validation, validation_verifier: validation_verifier,
                                       reread: -> { green }, clock: expiry_clock,
                                       remote_head_reader: -> { head })
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
  elsif ARGV.empty?
    begin
      input = AutomationDispatch.read_live
      output = AutomationDispatch.dry_run(input, reread: -> { AutomationDispatch.read_live })
    rescue AutomationDecision::Invalid, SystemCallError => e
      output = AutomationDispatch.stop([e.message])
    end
    puts output['status']
    puts JSON.pretty_generate(output)
  else
    warn 'Usage: ruby scripts/automation_dispatch.rb [--self-test | --prelaunch-self-test | --prelaunch]'
    exit 2
  end
end
