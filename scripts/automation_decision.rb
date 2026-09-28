#!/usr/bin/env ruby
# Decision-only FOOD AI routing consumer. It never starts tasks or writes files.
require 'json'
require 'digest'
require 'open3'
require 'time'
require 'yaml'

module AutomationDecision
  ROOT = File.expand_path('..', __dir__)
  PROTECTED = %w[
    ios/calorietracker.xcodeproj/project.pbxproj
    ios/calorietracker.xcodeproj/xcshareddata/xcschemes/calorietracker.xcscheme
    ios/calorietracker/Info.plist
    ios/calorietracker/InfoPlist.xcstrings
    ios/calorietracker/LocalModels.xcstrings
    ios/calorietracker/Localizable.xcstrings
    ios/calorietracker/WeeklyChallenge.xcstrings
    ios/calorietracker/Views/FoodResultView.swift
    ios/calorietrackerUITests/SearchFoodAcceptanceUITests.swift
  ].freeze
  ROUTING_FILES = %w[AUTOMATION_POLICY.md CURRENT_HANDOFF.md NEXT_TASK.md].freeze
  Doc = Struct.new(:data, :body)

  class Invalid < StandardError; end

  def self.keys!(value, required, optional, label)
    raise Invalid, "#{label}: expected mapping" unless value.is_a?(Hash)
    missing = required - value.keys
    unsupported = value.keys - required - optional
    raise Invalid, "#{label}: missing #{missing.join(', ')}" unless missing.empty?
    raise Invalid, "#{label}: unsupported #{unsupported.join(', ')}" unless unsupported.empty?
  end

  def self.unique_yaml_keys!(node)
    if node.is_a?(Psych::Nodes::Mapping)
      names = node.children.each_slice(2).map do |key, value|
        raise Invalid, 'YAML: non-scalar key' unless key.is_a?(Psych::Nodes::Scalar)
        unique_yaml_keys!(value)
        key.value
      end
      raise Invalid, 'YAML: duplicate key' unless names.uniq.length == names.length
    elsif node.respond_to?(:children) && node.children
      node.children.each { |child| unique_yaml_keys!(child) }
    end
  end

  def self.front_matter(text, label)
    match = text.match(/\A---\r?\n(.*?)\r?\n---(?:\r?\n|\z)/m)
    raise Invalid, "#{label}: missing or malformed front matter" unless match
    unique_yaml_keys!(Psych.parse(match[1]))
    data = YAML.safe_load(match[1], aliases: false)
    raise Invalid, "#{label}: expected mapping" unless data.is_a?(Hash)
    Doc.new(data, text[match.end(0)..])
  rescue Psych::Exception => e
    raise Invalid, "#{label}: invalid YAML (#{e.class})"
  end

  def self.policy!(doc)
    data = doc.data
    keys!(data, %w[schema_version handoff_file next_task_file states lane_precedence risk_lanes defaults forced_hold], [], 'policy')
    raise Invalid, 'policy: unsupported schema' unless data['schema_version'] == 1
    raise Invalid, 'policy: unsupported file names' unless data.values_at('handoff_file', 'next_task_file') == %w[CURRENT_HANDOFF.md NEXT_TASK.md]
    raise Invalid, 'policy: unsupported states' unless data['states'] == %w[COMPLETE HOLD BLOCKED DECISION_REQUIRED]
    raise Invalid, 'policy: unsupported lanes' unless data['lane_precedence'] == %w[RED AMBER GREEN]
    keys!(data['risk_lanes'], %w[GREEN AMBER RED], [], 'risk_lanes')
    keys!(data['defaults'], %w[auto_start_allowed commit_allowed push_allowed], [], 'defaults')
    raise Invalid, 'policy: unsafe defaults' unless data['defaults'].values.all? { |v| v == false }
    keys!(data['forced_hold'], %w[flaky_or_incomplete_validation protected_file_write_or_conflict scope_expansion human_or_product_choice], [], 'forced_hold')
    raise Invalid, 'policy: unsupported forced holds' unless data['forced_hold'].values_at('flaky_or_incomplete_validation', 'protected_file_write_or_conflict', 'scope_expansion', 'human_or_product_choice') == %w[AMBER AMBER AMBER RED]
  end

  def self.handoff!(doc)
    data = doc.data
    keys!(data, %w[schema_version state risk_lane last_task_status last_task_risk_lane auto_start_allowed human_decision_required next_task_envelope validation_evidence_ref], [], 'handoff')
    raise Invalid, 'handoff: unsupported schema' unless data['schema_version'] == 1
    raise Invalid, 'handoff: invalid status/lane' unless %w[COMPLETE HOLD BLOCKED DECISION_REQUIRED].include?(data['state']) && %w[GREEN AMBER RED].include?(data['risk_lane']) && %w[COMPLETE HOLD BLOCKED DECISION_REQUIRED].include?(data['last_task_status']) && %w[GREEN AMBER RED].include?(data['last_task_risk_lane'])
    raise Invalid, 'handoff: invalid booleans' unless [data['auto_start_allowed'], data['human_decision_required']].all? { |v| v == true || v == false }
    raise Invalid, 'handoff: unsupported references' unless data['next_task_envelope'] == 'NEXT_TASK.md' && data['validation_evidence_ref'] == '#validation' && doc.body.match?(/^## Validation\s*$/)
  end

  def self.task!(doc)
    data = doc.data
    required = %w[schema_version state risk_lane title goal execution_target allowed_files forbidden_files validation_required auto_start_allowed human_decision_required commit_allowed push_allowed stop_conditions]
    keys!(data, required, %w[task_id read_only max_tasks max_duration_minutes], 'task')
    raise Invalid, 'task: unsupported schema' unless data['schema_version'] == 1
    raise Invalid, 'task: invalid status/lane' unless %w[COMPLETE HOLD BLOCKED DECISION_REQUIRED].include?(data['state']) && %w[GREEN AMBER RED].include?(data['risk_lane'])
    raise Invalid, 'task: invalid execution_target' unless %w[cloud_clean_checkout local_working_tree].include?(data['execution_target'])
    raise Invalid, 'task: missing title/goal' unless %w[title goal].all? { |k| data[k].is_a?(String) && !data[k].strip.empty? }
    raise Invalid, 'task: invalid booleans' unless %w[auto_start_allowed human_decision_required commit_allowed push_allowed].all? { |k| data[k] == true || data[k] == false }
    raise Invalid, 'task: invalid read_only' if data.key?('read_only') && data['read_only'] != true
    %w[max_tasks max_duration_minutes].each do |key|
      raise Invalid, "task: invalid #{key}" if data.key?(key) && (!data[key].is_a?(Integer) || data[key] <= 0)
    end
    %w[allowed_files forbidden_files validation_required stop_conditions].each do |key|
      raise Invalid, "task: invalid #{key}" unless data[key].is_a?(Array) && !data[key].empty? && data[key].all? { |v| v.is_a?(String) && !v.strip.empty? }
    end
  end

  def self.git_value(*args)
    output, status = Open3.capture2e('git', '-C', ROOT, *args)
    raise Invalid, "git #{args.first}: unavailable" unless status.success?
    output.strip
  end

  def self.live_git
    raw, status = Open3.capture2e('git', '-C', ROOT, 'status', '--porcelain=v1', '-z', '--untracked-files=all')
    raise Invalid, 'git status: unavailable' unless status.success?
    entries = porcelain_entries(raw)
    {
      'branch' => git_value('branch', '--show-current'),
      'head' => git_value('rev-parse', 'HEAD'),
      'remote_head' => git_value('rev-parse', 'origin/main'),
      'entries' => entries
    }
  end

  def self.porcelain_entries(raw)
    raw.split("\0").map { |line| [line[0, 2], line[3..]] }
  end

  def self.matches?(pattern, path)
    return path.start_with?(pattern.delete_suffix('**')) if pattern.end_with?('/**')
    return false if pattern.match?(/[\*?\[]/)
    pattern == path
  end

  def self.protected_reason(task, git)
    allowed = task['allowed_files']
    forbidden = task['forbidden_files']
    return 'unsafe allowed path' unless allowed.all? { |path| path.is_a?(String) && !path.start_with?('/', '.') && !path.include?('..') && !path.match?(/[\*?\[]/) }
    return 'protected paths not excluded' unless PROTECTED.all? { |path| forbidden.any? { |glob| matches?(glob, path) } }
    return 'allowed path intersects forbidden/protected files' if allowed.any? { |path| PROTECTED.include?(path) || forbidden.any? { |glob| matches?(glob, path) } }
    return 'wrong branch or unsynchronized HEAD' unless git['branch'] == 'main' && git['head'] == git['remote_head']
    return 'invalid Git state' unless git['entries'].is_a?(Array)
    if task['execution_target'] == 'cloud_clean_checkout'
      return 'routing checkpoint differs from HEAD' if git['entries'].any? do |_status, path|
        ROUTING_FILES.include?(path) || path.start_with?('scripts/automation_')
      end
      return nil
    end
    git['entries'].each do |status, path|
      return 'staged, conflicted, or renamed Git state' unless status == ' M' || status == '??'
      return 'unexpected working-tree change' unless forbidden.any? { |glob| matches?(glob, path) }
    end
    nil
  end

  def self.approval!(approval)
    keys!(approval, %w[schema_version approved_tasks max_tasks tasks_completed max_duration_minutes started_at expires_at commit_allowed push_allowed], [], 'approval')
    raise Invalid, 'approval: unsupported schema' unless approval['schema_version'] == 1
    raise Invalid, 'approval: invalid task list' unless approval['approved_tasks'].is_a?(Array) && !approval['approved_tasks'].empty? && approval['approved_tasks'].all? { |entry| entry.is_a?(Hash) && entry.keys.sort == %w[id sha256] && entry['id'].is_a?(String) && !entry['id'].empty? && entry['sha256'].is_a?(String) && entry['sha256'].match?(/\A[0-9a-f]{64}\z/) }
    raise Invalid, 'approval: invalid bounds' unless approval['max_tasks'].is_a?(Integer) && approval['max_tasks'] > 0 && approval['tasks_completed'].is_a?(Integer) && approval['tasks_completed'] >= 0 && approval['max_duration_minutes'].is_a?(Integer) && approval['max_duration_minutes'] > 0
    raise Invalid, 'approval: commit/push not supported by decision-only tool' unless approval['commit_allowed'] == false && approval['push_allowed'] == false
    %w[started_at expires_at].each { |key| raise Invalid, "approval: invalid #{key}" unless approval[key].is_a?(String) }
  end

  def self.canonical(value)
    return value.keys.sort.to_h { |key| [key, canonical(value[key])] } if value.is_a?(Hash)
    return value.map { |item| canonical(item) } if value.is_a?(Array)
    value
  end

  def self.task_digest(task)
    Digest::SHA256.hexdigest(JSON.generate(canonical(task)))
  end

  # Repository-only eligibility. Neither a repository file nor an approval
  # argument can establish external validation or authenticated human consent.
  def self.decide(policy, handoff, task, git:, now: Time.now.utc)
    policy!(policy)
    handoff!(handoff)
    task!(task)
    h, t = handoff.data, task.data
    reasons = []
    reasons << 'contradictory handoff/envelope state' unless h['state'] == t['state']
    reasons << 'contradictory handoff/envelope risk lane' unless h['risk_lane'] == t['risk_lane']
    reasons << "state #{h['state']}" unless h['state'] == 'COMPLETE'
    reasons << "risk lane #{h['risk_lane']}" unless h['risk_lane'] == 'GREEN'
    reasons << 'last task not complete' unless h['last_task_status'] == 'COMPLETE'
    reasons << 'auto_start_allowed false' unless h['auto_start_allowed'] == true && t['auto_start_allowed'] == true
    reasons << 'human decision required' unless h['human_decision_required'] == false && t['human_decision_required'] == false
    reasons << 'commit/push permission requested' unless t['commit_allowed'] == false && t['push_allowed'] == false
    return result(t, reasons) unless reasons.empty?

    reasons << 'missing stable task_id' unless t['task_id'].is_a?(String) && !t['task_id'].strip.empty?
    protection = protected_reason(t, git)
    reasons << protection if protection
    result(t, reasons)
  rescue Invalid => e
    result(task&.data || {}, [e.message])
  end

  def self.result(task, reasons)
    allowed = reasons.empty?
    output = { 'decision' => allowed ? 'READY_FOR_APPROVAL' : 'STOP: HOLD', 'reasons' => reasons, 'task' => { 'id' => task['task_id'], 'title' => task['title'], 'goal' => task['goal'] }, 'dispatched' => false }
    output['task']['allowed_files'] = task['allowed_files'] if allowed
    output['task']['validation_required'] = task['validation_required'] if allowed
    output['task']['digest'] = task_digest(task) if allowed
    output
  end

  def self.read_live
    files = %w[AUTOMATION_POLICY.md CURRENT_HANDOFF.md NEXT_TASK.md].map do |name|
      front_matter(File.read(File.join(ROOT, name)), name)
    end
    decide(*files, git: live_git)
  rescue Errno::ENOENT, Invalid => e
    result({}, [e.message])
  end

  def self.fixture(data, body)
    front_matter("#{YAML.dump(data)}---\n#{body}", 'synthetic fixture')
  end

  def self.self_test
    policy = front_matter(File.read(File.join(ROOT, 'AUTOMATION_POLICY.md')), 'policy')
    handoff = front_matter(File.read(File.join(ROOT, 'CURRENT_HANDOFF.md')), 'handoff')
    task = front_matter(File.read(File.join(ROOT, 'NEXT_TASK.md')), 'task')
    head = 'a' * 40
    git = { 'branch' => 'main', 'head' => head, 'remote_head' => head, 'entries' => [] }
    now = Time.now.utc
    green_h = fixture(handoff.data.merge('state' => 'COMPLETE', 'risk_lane' => 'GREEN', 'auto_start_allowed' => true), handoff.body)
    green_t = fixture(task.data.merge('state' => 'COMPLETE', 'risk_lane' => 'GREEN', 'auto_start_allowed' => true, 'execution_target' => 'local_working_tree', 'task_id' => 'safe-doc-audit', 'title' => 'Check routing documentation links', 'goal' => 'Read the routing documentation and report broken local links.', 'validation_required' => ['Record the checked links and an exit-zero validation result.']), task.body)
    hold_h = fixture(handoff.data.merge('state' => 'HOLD', 'risk_lane' => 'AMBER', 'auto_start_allowed' => false), handoff.body)
    hold_t = fixture(task.data.merge('state' => 'HOLD', 'risk_lane' => 'AMBER', 'auto_start_allowed' => false), task.body)
    plan = { 'schema_version' => 1, 'approved_tasks' => [{ 'id' => 'safe-doc-audit', 'sha256' => task_digest(green_t.data) }], 'max_tasks' => 1, 'tasks_completed' => 0, 'max_duration_minutes' => 15, 'started_at' => (now - 60).iso8601, 'expires_at' => (now + 600).iso8601, 'commit_allowed' => false, 'push_allowed' => false }
    cases = {
      'synthetic_hold' => [hold_h, hold_t, nil, 'STOP: HOLD'],
      'synthetic_green' => [green_h, green_t, plan, 'READY_FOR_APPROVAL'],
      'no_self_referential_validation' => [green_h, green_t, nil, 'READY_FOR_APPROVAL'],
      'auto_start_false' => [green_h, Doc.new(green_t.data.merge('auto_start_allowed' => false), green_t.body), plan, 'STOP: HOLD'],
      'amber' => [Doc.new(green_h.data.merge('risk_lane' => 'AMBER'), green_h.body), Doc.new(green_t.data.merge('risk_lane' => 'AMBER'), green_t.body), plan, 'STOP: HOLD'],
      'red' => [Doc.new(green_h.data.merge('risk_lane' => 'RED'), green_h.body), Doc.new(green_t.data.merge('risk_lane' => 'RED'), green_t.body), plan, 'STOP: HOLD'],
      'protected_file' => [green_h, Doc.new(green_t.data.merge('allowed_files' => ['ios/calorietracker/Info.plist']), green_t.body), plan, 'STOP: HOLD'],
      'contradictory_state' => [Doc.new(green_h.data.merge('state' => 'HOLD'), green_h.body), green_t, plan, 'STOP: HOLD'],
      'last_task_incomplete' => [Doc.new(green_h.data.merge('last_task_status' => 'HOLD'), green_h.body), green_t, plan, 'STOP: HOLD'],
      'human_decision' => [Doc.new(green_h.data.merge('human_decision_required' => true), green_h.body), green_t, plan, 'STOP: HOLD'],
      'embedded_validation_rejected' => [Doc.new(green_h.data.merge('validation' => { 'head' => head }), green_h.body), green_t, plan, 'STOP: HOLD'],
      'missing_approval' => [green_h, green_t, nil, 'READY_FOR_APPROVAL'],
      'changed_task_details' => [green_h, Doc.new(green_t.data.merge('goal' => 'A different goal'), green_t.body), plan, 'READY_FOR_APPROVAL'],
      'expired_approval' => [green_h, green_t, plan.merge('expires_at' => (now - 1).iso8601), 'READY_FOR_APPROVAL'],
      'unsupported_field' => [Doc.new(green_h.data.merge('unknown' => true), green_h.body), green_t, plan, 'STOP: HOLD']
    }
    cases['missing_field'] = [Doc.new(green_h.data.reject { |key, _| key == 'state' }, green_h.body), green_t, plan, 'STOP: HOLD']
    failures = 0
    cases.each do |name, (h, t, _auth, expected)|
      actual = decide(policy, h, t, git: git, now: now)
      failures += 1 unless actual['decision'] == expected
      puts JSON.generate({ 'case' => name }.merge(actual))
    end
    %w[duplicate_key malformed_yaml].each do |name|
      input = name == 'duplicate_key' ? "---\nstate: HOLD\nstate: COMPLETE\n---\n" : "---\nstate: [\n---\n"
      begin
        front_matter(input, name)
        failures += 1
        puts JSON.generate('case' => name, 'decision' => 'UNEXPECTED_ACCEPT')
      rescue Invalid => e
        puts JSON.generate('case' => name, 'decision' => 'STOP: HOLD', 'reasons' => [e.message], 'dispatched' => false)
      end
    end
    preserved = porcelain_entries(" M ios/calorietracker/Info.plist\0")
    failures += 1 unless preserved == [[' M', 'ios/calorietracker/Info.plist']]
    puts JSON.generate('case' => 'unstaged_porcelain_status', 'passed' => preserved == [[' M', 'ios/calorietracker/Info.plist']], 'dispatched' => false)
    cloud_t = fixture(green_t.data.merge('execution_target' => 'cloud_clean_checkout'), green_t.body)
    target_cases = {
      'cloud_ignores_unrelated_mac_edit' => [cloud_t, git.merge('entries' => [[' M', PROTECTED.first]]), 'READY_FOR_APPROVAL'],
      'cloud_rejects_dirty_routing_file' => [cloud_t, git.merge('entries' => [[' M', ROUTING_FILES.first]]), 'STOP: HOLD'],
      'local_rejects_unrelated_edit' => [green_t, git.merge('entries' => [[' M', 'unrelated.txt']]), 'STOP: HOLD'],
      'invalid_execution_target' => [fixture(green_t.data.merge('execution_target' => 'unknown'), green_t.body), git, 'STOP: HOLD']
    }
    target_cases.each do |name, (candidate, state, expected)|
      actual = decide(policy, green_h, candidate, git: state, now: now)
      failures += 1 unless actual['decision'] == expected && actual['dispatched'] == false
      puts JSON.generate({ 'case' => name }.merge(actual))
    end
    changed_digest = task_digest(green_t.data) != task_digest(cloud_t.data)
    failures += 1 unless changed_digest
    puts JSON.generate('case' => 'execution_target_changes_digest', 'passed' => changed_digest, 'dispatched' => false)
    puts "self_test=#{failures.zero? ? 'PASS' : 'FAIL'} cases=#{cases.length + 8} failures=#{failures} dispatched=0"
    exit(failures.zero? ? 0 : 1)
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV == ['--self-test']
    AutomationDecision.self_test
  elsif ARGV.empty?
    begin
      output = AutomationDecision.read_live
    rescue AutomationDecision::Invalid => e
      output = AutomationDecision.result({}, [e.message])
    end
    puts output['decision']
    puts JSON.pretty_generate(output)
  else
    warn 'Usage: ruby scripts/automation_decision.rb [--self-test]'
    exit 2
  end
end
