module CapistranoMulticonfigParallel
  # class used to determine the invocation chain for a task
  class RakeInvocationChain


    delegate :task_hooks,
    to: :CapistranoMulticonfigParallel

    attr_accessor :task, :env, :job_id

    def initialize(env, task)
      @env = env
      @task = task
      @job_id = @env[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
    end

    def strip_characters_from_string(value)
      return '' if value.blank?
      value = value.delete("\r\n").delete("\n")
      value = value.gsub(/\s+/, ' ').strip
      value
    end

    def string_interpolated?(string)
      string.include?('#{') || string.include?('+') || string.include?('<')
    end

    def log_to_file(*args)
      puts args
    end

    def task_name(task_obj = @task)
      task_obj.respond_to?(:name) ? task_obj.name : task_obj
    end

    def register_hooks(deps, &block)
      return if @job_id.present?
      hooks_for_task(task_name)
      register_before_hook(deps)
      new_block = block_given? ? block.dup : proc {}
      register_after_hook(&new_block)
    end

    private

    def register_before_hook(deps)
      return if deps.blank?
      log_to_file("BEFORE Enhancing task #{task_name} with #{deps.inspect}")
      deps.each do |dependency|
        register_hook_for_task('before', dependency)
      end
    end

    def register_after_hook(&block)
      source = block_given? ? fetch_block_source(&block) : nil
      return if source.blank?
      #  log_to_file("AFTER Enhancing task #{task_name} with #{source}")
      tasks = parse_source_block(source, &block)
      register_after_tasks(tasks, &block)
    end

    def register_after_tasks(tasks)
      return if tasks.blank?
      tasks.each do |task_string|
        register_hook_for_task('after', task_string)
      end
    end

    def fetch_block_source(&block)
      block.source
    rescue => exception
      log_to_file(exception)
      nil
    end

    def evaluate_task(task_string, &block)
      block_given? ? block.binding.eval(task_string) : task_string
    rescue => exception
      log_to_file(exception, task_string)
      task_string
    end

    def hooks_for_task(task)
      current_task_node = task_hooks.task_node(task)

      unless current_task_node.present?
        current_task_node = new_node(task)
      end
      current_task_node
    end

    def new_node(task, parent = nil)
      return unless task.present?
      task = task.is_a?(Rake::Task) ? task.name : task
      node = CapistranoMulticonfigParallel::RakeTreeNode.new(task, {})
      if parent.present?
        parent << node
      else
        task_hooks << node if task_hooks.task_node(task).blank?
      end
      node
    end

    def register_hook_for_task(hook_name, obj)
      node =  new_node(task_name(obj))
      begin
        current_task_node = hook_name == 'before' ? hooks_for_task(task_name) : hooks_for_task(task_name(obj))
        if obj.present? && current_task_node.present?
          node.content[hook_name] = CapistranoMulticonfigParallel::RakeTreeNode.new(hook_name, {}) if node.content[hook_name].blank?
          node.content[hook_name].add(current_task_node)
        end
      end
    end

    # def task_insert_position(hook_name)
    #   current_index = job_chain_task_index(@job_id, task_name)
    #   current_index = current_index.present? ? current_index : 0
    #   log_to_file("Task #{task_name} is at position #{current_index} #{fetch_invocation_chains}")
    #   current_index.send((hook_name == 'after') ? '+' : '-', 1)
    # end
    #
    # def register_hook_for_task(hook_name, obj)
    #   new_task = task_name(obj)
    #   log_to_file("REGISTER #{task_name} #{hook_name} #{new_task} #{task_insert_position(hook_name)} #{fetch_invocation_chains}")
    #   if new_task.is_a?(Array)
    #     new_task.each do |task|
    #       register_hook_for_task(hook_name, task)
    #     end
    #   else
    #     get_job_invocation_chain(@job_id, new_task, task_insert_position(hook_name))
    #   end
    # end

    def parse_source_block(source, &block)
      source_tasks = []
      source.scan(Regexp.union(/(\S+)\.invoke\b/, /(?<!\S)invoke\s{1}(\S+)/, /^Rake\:\:Task\[(.*?)\]/, /load\s*\(?(\S+)\)?/)).each do |match|
        match = match.uniq.compact
        log_to_file("REGEX #{match}")
        get_task_match(source_tasks, match, source, &block)
      end
      source_tasks
    end

    def get_task_match(source_tasks, match_array, source, &block)
      new_match = match_array.reject(&:blank?)
      new_match.each do|match_task|
        string = parse_string_enclosed_quotes(source, match_task, &block)
        source_tasks << string if string.present?
      end
    end

    def parse_string_enclosed_quotes(source, match_task, &block)
      new_match = match_task.scan(/^[\\'"]+(.*?)[\\'"]+/).join
      match_task = new_match.present? ? new_match : match_task
      parse_task_dynamic(source, match_task, &block)
    end

    def strip_code(code, task = '')
      code = strip_characters_from_string(code)
      code.gsub(/\//, '').gsub('.each', '.map').gsub("#{task}.invoke", task).gsub('invoke', '')
    end


    def parse_file_content(match_task)
      filename = match_task.to_s.include?('config/') ? File.join(CapistranoMulticonfigParallel.send(:detect_root), match_task.to_s) : match_task.to_s
      loaded_file = Gem.find_files(filename).first
      log_to_file("GEM FOUND #{filename.inspect} #{loaded_file.inspect}")
      if loaded_file.present?
        file_source = File.read(loaded_file)
        log_to_file("LOADED FILES for  #{task_name} found #{loaded_file} #{file_source}") if loaded_file.present?
        tasks = parse_source_block(file_source)
        register_after_tasks(tasks)
      else
        match_task
      end
    end

    def parse_task_dynamic(source, match_task, &block)
      log_to_file("AFTER #{task_name} DO #{match_task.inspect} #{string_interpolated?(match_task).inspect}")
      if string_interpolated?(match_task)
        new_source = strip_code(source.dup)
        new_source.scan(/\%w\{(.*?end+.*?)end/m).map do|code|
          get_tasks_from_code(strip_code('%w{' + code.join), &block)
        end.compact.flatten
      else
        match_task.present? ? get_tasks_from_code(match_task, &block) : ''
      end
    end

    def get_tasks_from_code(code, &block)
      tasks = evaluate_task(code, &block)
      tasks = tasks.is_a?(Array) ? tasks : [tasks]
      tasks.reject(&:blank?)
      tasks.map { |new_task| parse_file_content(new_task)  }.compact
    end
  end
end
