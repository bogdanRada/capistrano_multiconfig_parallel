# frozen_string_literal: true
module CapistranoMulticonfigParallel
  # class that handles the states of the celluloid worker executing the child process in a fork process
  class StateMachine
    include ComposableStateMachine::CallbackRunner
    attr_accessor :job, :actor, :initial_state, :state

    def initialize(job, actor)
      @job = job
      @actor = actor
      @initial_state = @job.status
      machine
    end

    def go_to_transition(action, options = {})
      return if @job.status.to_s.casecmp('dead').zero?
      transitions.on(action, state.to_s => action)
      @job.status = action
      if options[:bundler]
        @job.bundler_status = action
        actor_notify_state_change(state, 'preparing_app_bundle_install', action)
      else
        @job.bundler_status = nil
        machine.trigger(action)
      end
    end

    def machine
      @machine ||= ComposableStateMachine::MachineWithExternalState.new(
        model, method(:state), method(:state=), state: @initial_state.to_s, callback_runner: self
      )
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
      return unless @actor.alive?
      @actor.log_to_file("statemachine #{@job.id} triest to transition from #{@current_state} to  #{new_state} for event #{event}")
      @actor.async.send_msg(CapistranoMulticonfigParallel::TerminalTable.topic, type: 'event', new_state: new_state, current_state: current_state, event: event, message: "Going from #{current_state} to #{new_state}  due to a #{event} event")
    end
  end
end
