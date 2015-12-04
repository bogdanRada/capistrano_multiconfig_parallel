module CapistranoMulticonfigParallel
  # class that handles the states of the celluloid worker executing the child process in a fork process
  class StateMachine
    include ComposableStateMachine::CallbackRunner
    attr_accessor :job, :actor, :initial_state, :state, :output

    def initialize(job, actor)
      @job = job
      @actor = actor
      @initial_state = :unstarted
      machine
    end

    def go_to_transition(action)
      machine.trigger(action.to_s)
    end

    def machine
      @machine ||= ComposableStateMachine::MachineWithExternalState.new(
        model, method(:state), method(:state=), state: @initial_state.to_s, callback_runner: self)
      @machine
    end

    def transitions
      @transitions ||= ComposableStateMachine::Transitions.new
      @transitions
    end

    def model
      ComposableStateMachine.model(
        transitions: transitions,
        behaviors: {
          enter: {
            any: proc do |current_state, event, new_state|
              actor_notify_state_change(current_state, event, new_state)
            end
          }
        },
        initial_state: @initial_state
      )
    end

  private

    def actor_notify_state_change(current_state, event, new_state)
      @actor.send_msg(CapistranoMulticonfigParallel::TerminalTable.topic, type: 'event', message: "Going from #{current_state} to #{new_state}  due to a #{event} event")
    end
  end
end
