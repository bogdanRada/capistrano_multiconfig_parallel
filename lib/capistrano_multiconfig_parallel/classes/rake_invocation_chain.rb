require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to determine the invocation chain for a task
  class RakeInvocationChain
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_accessor :task, :env, :job_id, :invocation_chain

    def initialize(env, task)
      @env = env
      @task = task
      @job_id = @env[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
      @invocation_chain ||= CapistranoMulticonfigParallel.invocation_chains[@job_id] || []
      task_index = @invocation_chain.index(task_name)
      @invocation_chain << task_name if task_index.blank?
    end



    def task_index
      @invocation_chain.index(task_name)
    end

    def task_name(task_obj = nil)
      new_task_obj = task_obj.present? ? task_obj : @task
      new_task_obj.respond_to?(:name) ? new_task_obj.name : new_task_obj
    end

    def register_hooks(deps, &block)
      register_before_hook(deps)
      register_after_hook(&block)
    end

    private

    def register_before_hook(deps)
      return if deps.blank?
      deps.each do |dependency|
        register_hook_for_task('before', dependency)
      end
    end

    def register_after_hook(&block)
      source = block_given? ? fetch_block_source(&block) : nil
      return if source.blank?
      tasks = parse_source_block(source)
      register_after_tasks(tasks)
    end

    def register_after_tasks(tasks)
      return if tasks.blank?
      tasks.each do |t|
        task_name = t[:scope].present? ? "#{t[:scope]}:#{t[:task]}" : t[:task]
        post_task = evaluate_task(task_name, &block)
        name_task = post_task.present? ? post_task : t[:task]
        register_hook_for_task('after', name_task)
      end
    end

    def fetch_block_source(&block)
      block.source
    rescue => exception
      log_error(exception, 'stderr')
      nil
    end

    def evaluate_task(_task, &_block)
      eval(task, block.binding)
    rescue => exception
      log_error(exception, 'stderr')
      nil
    end

    def evaluate_dynamic_string(_code)
      proc { eval(code) }.call
    rescue => exception
      log_error(exception, 'stderr')
      []
    end

    def task_insert_position(hook_name)
      task_index.send((hook_name == 'before') ? '+' : '-', 1)
    end

    def register_hook_for_task(hook_name, obj)
      @invocation_chain.insert(task_insert_position(hook_name), task_name(obj))
    end

    def parse_source_block(source)
      source_tasks = source.scan(Regexp.union(/(\S+)\.invoke\b/, /(?<!\S)invoke\s{1}(\S+)/)).map do |match|
        match.reject(&:blank?).join.map do|task|
          parse_source_task_string(source, task)
        end
        source_tasks.present? ? source_tasks : []
      end
    end

    def parse_source_task_string(source, task)
      if task.include?('Rake::Task[')
        task.scan(/^Rake\:\:Task\[(.*?)\]/).each { |name| parse_string_enclosed_quotes(source, name) }
      else
        parse_string_enclosed_quotes(source, task)
      end
    end

    def parse_string_enclosed_quotes(source, task)
      task = task.scan(/[\\'"]+(.*?)[\\'"]+/).join
      parse_task_dynamic(source, task)
    end

    def strip_code(code, task = '')
      code = strip_characters_from_string(code)
      code.gsub(/\//, '').gsub('.each', '.map').gsub("#{task}.invoke", task).gsub('invoke', '')
    end

    def parse_task_dynamic(source, task)
      if string_interpolated?(task)
        new_source = strip_code(source.dup)
        new_source.scan(/\%w\{(.*?end+.*?)end/m).map do|code|
          get_tasks_from_code(code)
        end.flatten
      else
        task.present? ? task : []
      end
    end

    def get_tasks_fron_code(code)
      code = strip_code('%w{' + code.join)
      tasks = evaluate_dynamic_string(code)
      tasks.reject(&:blank?)
      tasks.map { |new_task| new_task }
    end
  end
end
