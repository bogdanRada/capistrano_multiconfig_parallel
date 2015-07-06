require_relative './rake_worker'
module CapistranoMulticonfigParallel
  # class that handles the rake task and waits for approval from the celluloid worker
  class IoWorker < CapistranoMulticonfigParallel::RakeWorker
    include Celluloid
    include Celluloid::Logger

    attr_accessor :stdin_result

    
    def custom_attributes
      @stdin_result =  ""
      super
    end
   
    
    def debug_enabled?
      true
    end

    def publish_new_work(env, new_options = {})
      @task_approved = false
      work(env, @options.merge(new_options)) 
    end
   
  
    def on_message(message)
      debug("Rake worker #{find_job_id} received after parse #{message}") if debug_enabled?
      if @client.succesfull_subscription?(message)
        debug("Rake worker #{find_job_id} received  parse #{message}") if debug_enabled?
        @successfull_subscription = true
      elsif message.present? && message['client_action'].blank?
        task_approval(message)
      else
        warn "unknown action: #{message.inspect}" if debug_enabled?
      end
    end

    def task_approval(message)
      if @job_id.to_i == message['job_id'].to_i  && message['approved'] == 'yes'
        @task_approved = true
        @stdin_result = message
      else
        warn "unknown invocation #{message.inspect}" if debug_enabled?
      end
    end


  end
end
