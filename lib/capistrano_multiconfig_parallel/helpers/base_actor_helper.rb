require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # base actor used for compatibility between celluloid versions
  module BaseActorHelper

    module ClassMethods
      class << self
        include CapistranoMulticonfigParallel::ApplicationHelper
        attr_reader :config


        def config
          {
            'logger_class' => celluloid_logger_class
          }
        end

        def boot_up
          celluloid_running = begin
                                Celluloid.running?
                              rescue StandardError
                                false
                              end
          Celluloid.boot unless celluloid_running
        end

        def celluloid_logger_class
          if version_less_than_seventeen?
            Celluloid::Logger
          else
            Celluloid::Internals::Logger
          end
        end

        def celluloid_version
          find_loaded_gem_property('celluloid', 'version')
        end

        def version_less_than_seventeen?
          verify_gem_version(celluloid_version, '0.17', operator: '<')
        end

        def version_less_than_eigthteen?
          verify_gem_version(celluloid_version, '0.18', operator: '<')
        end
      end
    end

    module InstanceMethods
      
      [
        :version_less_than_seventeen?,
      ].each do |method_name|
        define_method(method_name) do
          CapistranoMulticonfigParallel::BaseActorHelper::ClassMethods.send(method_name)
        end
      end

      def setup_actor_supervision_details(class_name, options)
        arguments = (options[:args].is_a?(Array) ? options[:args] : [options[:args]]).compact
        if version_less_than_seventeen?
          [options[:actor_name], options[:type], *arguments]
        else
          #supervises_opts = options[:supervises].present? ? { supervises: options[:supervises] } : {}
          { as: options[:actor_name], type: options[:type], args: arguments, size: options.fetch(:size, nil) }
        end
      end


      def setup_actor_supervision(class_name, options)
        if version_less_than_seventeen?
          class_name.supervise_as(*setup_actor_supervision_details(class_name, options))
        else
          class_name.supervise setup_actor_supervision_details(class_name, options)
        end
      end

      def setup_supervision_group
        if version_less_than_seventeen?
          Celluloid::SupervisionGroup.run!
        else
          Celluloid::Supervision::Container.run!
        end
      end

      def setup_pool_of_actor(class_name, options)
        if version_less_than_seventeen?
          class_name.pool(options[:type], as: options[:actor_name], size:  options.fetch(:size, 10))
        else
          # config = Celluloid::Supervision::Configuration.new
          # config.define setup_actor_supervision_details(class_name, options)
          options = setup_actor_supervision_details(class_name, options)
          class_name.pool *[options[:type], options.except(:type)]
        end
      end
    end


    def self.included(base)
      base.send(:include, Celluloid)
      base.send(:include, Celluloid::Notifications)
      base.send(:include, CapistranoMulticonfigParallel::ApplicationHelper)
      base.send(:include, CapistranoMulticonfigParallel::BaseActorHelper::ClassMethods.config['logger_class'])
      base.send(:include, CapistranoMulticonfigParallel::BaseActorHelper::InstanceMethods)
    end

  end
end

if CapistranoMulticonfigParallel::BaseActorHelper::ClassMethods.version_less_than_seventeen?
  require 'celluloid'
  require 'celluloid/autostart'
elsif CapistranoMulticonfigParallel::BaseActorHelper::ClassMethods.version_less_than_eigthteen?
  require 'celluloid/current'
  CapistranoMulticonfigParallel::BaseActorHelper::ClassMethods.boot_up
  require 'celluloid'
else
  require 'celluloid'
  require 'celluloid/pool'
  require 'celluloid/fsm'
  require 'celluloid/supervision'
  CapistranoMulticonfigParallel::BaseActorHelper::ClassMethods.boot_up
end
