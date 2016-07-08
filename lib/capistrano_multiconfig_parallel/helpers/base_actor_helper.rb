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
      end
    end

    module InstanceMethods
      delegate :version_less_than_seventeen?,
      to: :'CapistranoMulticonfigParallel::BaseActorHelper::ClassMethods'


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
          setup_supervision_group do |supervisor|
            supervisor.supervise setup_actor_supervision_details(class_name, options)
          end
        end
      end

      def setup_supervision_group
        if version_less_than_seventeen?
          Celluloid::SupervisionGroup.run!
        else
          Class.new(Celluloid::Supervision::Container) do
            yield(self) if block_given?
          end.run!
        end
      end

      def setup_pool_of_actor(class_name, options)
        if version_less_than_seventeen?
          class_name.pool(options[:type], as: options[:actor_name], size:  options.fetch(:size, 10))
        else
          options = setup_actor_supervision_details(class_name, options)
          setup_supervision_group do |supervisor|
            supervisor.pool *[options[:type], options.except(:type)]
          end
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
  require 'celluloid/autostart'
else
  require 'celluloid/current'
end
