module RakeDelegation
  
  #    def selective_delegation_methods(action)
#      allowed_methods =  action.to_s == "stdout" ?   %w{write puts print} : %w{gets}
#      allowed_methods.each do |meth|
#        define_singleton_method(meth) do |*arguments|
#          perform_delegate_action(action, meth, arguments)
#        end
#      end
#      allowed_methods
#    end
#
#    def  perform_delegate_action(action, _meth, arguments)
#      raise arguments.inspect
#      if action == "stdout"
#        user_prompt_needed?(arguments.join(" ")) if arguments.present?
#      else
#        wait_execution  until @stdin_result.present?
#        return @stdin_result
#      end
#    end
#    
#    
#    
#    def publish_question_event(question, default)
#      @client.publish(CapistranoMulticonfigParallel::TerminalTable::TOPIC, 'type' => 'stdout', 'job_id' => @job_id, 'question' => question, 'default' => default)
#    end

end
