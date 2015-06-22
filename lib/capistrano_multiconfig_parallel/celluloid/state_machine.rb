module CapistranoMulticonfigParallel
  # class that handles the states of the celluloid worker executing the child process in a fork process
  class StateMachine
    include ComposableStateMachine::CallbackRunner
    attr_accessor :state, :model, :machine, :job, :initial_state, :transitions, :output

    def initialize(job, actor)
      @job = job
      @actor = actor
      @initial_state = :unstarted
      @model = generate_model
      build_machine
    end

    def go_to_transition(action)
      @machine.trigger(action.to_s)
    end

  private

    def build_machine
      @machine = ComposableStateMachine::MachineWithExternalState.new(
        @model, method(:state), method(:state=), state: initial_state.to_s, callback_runner: self)
    end

    def generate_transitions
      @transitions = ComposableStateMachine::Transitions.new
      @transitions
    end

    def generate_model
      ComposableStateMachine.model(
        transitions: generate_transitions,
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

    def actor_notify_state_change(current_state, event, new_state)
      @actor.send_msg(CapistranoMulticonfigParallel::TerminalTable::TOPIC, type: 'event', message: "Going from #{current_state} to #{new_state}  due to a #{event} event")
    end
  end
end
