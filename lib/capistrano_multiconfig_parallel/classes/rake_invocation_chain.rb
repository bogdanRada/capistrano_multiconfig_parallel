require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to determine the invocation chain for a task
  class RakeInvocationChain
    include CapistranoMulticonfigParallel::ApplicationHelper

    delegate :get_job_invocation_chain,
    :fetch_invocation_chains,
    :job_chain_task_index,
    to: :CapistranoMulticonfigParallel

    attr_accessor :task, :env, :job_id

    def initialize(env, task)
      @env = env
      @task = task
      @job_id = @env[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
      log_to_file("Enhancing task #{task_name} #{fetch_invocation_chains}", job_id: @job_id)
      get_job_invocation_chain(@job_id, task_name)
      log_to_file("Enhancing_AFTER task #{task_name} #{fetch_invocation_chains}", job_id: @job_id)
    end

    def task_name(task_obj = nil)
      new_task_obj = task_obj.present? ? task_obj : @task
      new_task_obj.respond_to?(:name) ? new_task_obj.name : new_task_obj
    end

    def register_hooks(deps, &block)
      register_before_hook(deps)
      new_block = block_given? ?  block.dup : proc {}
      register_after_hook(&new_block)
    end

    private

    def register_before_hook(deps)
      return if deps.blank?
      log_to_file("BEFORE Enhancing task #{task_name} with #{deps.inspect}", job_id: @job_id)
      deps.each do |dependency|
        register_hook_for_task('before', dependency)
      end
    end

    def register_after_hook(&block)
      source = block_given? ? fetch_block_source(&block) : nil
      return if source.blank?
      log_to_file("AFTER Enhancing task #{task_name} with #{source}", job_id: @job_id)
      tasks = parse_source_block(source)
      register_after_tasks(tasks, &block)
      #block.call if source.include?('load') || source.include?('require')
    end

    def register_after_tasks(tasks, &block)
      return if tasks.blank?
      tasks.each do |task_string|
        register_hook_for_task('after', task_string)
      end
    end

    def fetch_block_source(&block)
      block.source
    rescue => exception
      log_error(exception, 'stderr')
      nil
    end

    # def evaluate_task(task_string, &block)
    #   eval(task_string, block.binding)
    # rescue => exception
    #   log_error(exception, 'stderr')
    #   task_string
    # end

    def evaluate_interpolated_string(code)
      proc { eval(code) }.call
    rescue => exception
      log_error(exception, 'stderr')
      []
    end

    def task_insert_position(hook_name)
       current_index =job_chain_task_index(@job_id, task_name)
       current_index =  current_index.present? ? current_index : 0
       log_to_file("Task #{task_name} is at position #{current_index} #{fetch_invocation_chains}", job_id: @job_id)
       current_index.send((hook_name == 'after') ? '+' : '-', 1)
    end

    def register_hook_for_task(hook_name, obj)
      new_task =  task_name(obj)
      log_to_file("REGISTER #{task_name} #{hook_name} #{new_task} #{task_insert_position(hook_name)} #{fetch_invocation_chains}", job_id: @job_id)
      if new_task.is_a?(Array)
        new_task.each do |task|
          register_hook_for_task(hook_name, task)
        end
      else
         get_job_invocation_chain(@job_id,new_task, task_insert_position(hook_name))
      end
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

    def get_tasks_from_code(code)
      code = strip_code('%w{' + code.join)
      tasks = evaluate_interpolated_string(code)
      tasks.reject(&:blank?)
      tasks.map { |new_task| new_task }.compact
    end
  end
end
