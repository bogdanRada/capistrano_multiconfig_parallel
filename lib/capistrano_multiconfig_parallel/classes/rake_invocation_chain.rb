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
      register_after_tasks(tasks, &block)
    end

    def register_after_tasks(tasks, &block)
      return if tasks.blank?
      tasks.each do |task_string|
        name_task = evaluate_task(task_string.to_s, &block)
        register_hook_for_task('after', name_task)
      end
    end

    def fetch_block_source(&block)
      block.source
    rescue => exception
      log_error(exception, 'stderr')
      nil
    end

    def evaluate_task(task_string, &block)
      eval(task_string, block.binding)
    rescue => exception
      log_error(exception, 'stderr')
      task_string
    end

    def evaluate_interpolated_string(code)
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
      source_tasks = []
      source.scan(Regexp.union(/(\S+)\.invoke\b/, /(?<!\S)invoke\s{1}(\S+)/, /^Rake\:\:Task\[(.*?)\]/)).each do |match|
        get_task_match(source_tasks, match, source)
      end
      source_tasks
    end

    def get_task_match(source_tasks, match_array, source)
       new_match = match_array.reject(&:blank?)
        new_match.each do|match_task|
          string = parse_string_enclosed_quotes(source, match_task)
          source_tasks << string if string.present?
        end
      end

    def parse_string_enclosed_quotes(source, match_task)
      match_task = match_task.scan(/[\\'"]+(.*?)[\\'"]+/).join
      parse_task_dynamic(source, match_task)
    end

    def strip_code(code, task = '')
      code = strip_characters_from_string(code)
      code.gsub(/\//, '').gsub('.each', '.map').gsub("#{task}.invoke", task).gsub('invoke', '')
    end

    def parse_task_dynamic(source, match_task)
      if string_interpolated?(match_task)
        new_source = strip_code(source.dup)
        new_source.scan(/\%w\{(.*?end+.*?)end/m).map do|code|
          get_tasks_from_code(code)
        end.compact.flatten
      else
        match_task.present? ? match_task : ''
      end
    end

    def get_tasks_fron_code(code)
      code = strip_code('%w{' + code.join)
      tasks = evaluate_interpolated_string(code)
      tasks.reject(&:blank?)
      tasks.map { |new_task| new_task }.compact
    end
  end
end
