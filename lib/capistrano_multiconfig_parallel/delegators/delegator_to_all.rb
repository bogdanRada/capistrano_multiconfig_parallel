# DelegateToAll. Like delegate.rb from Ruby's std lib but lets you have multiple target/delegate objects.

require 'delegate'

class DelegatorToAll < Delegator
  # Pass in the _obj_ to delegate method calls to.  All methods supported by
  # _obj_ will be delegated to.
  #
  attr_accessor :action
  
  def initialize(action, *targets)
    FileUtils.rm_rf(__log_file) if File.file?(__log_file)
    __action = action
    __setobj__(targets)
  end
  
  def __log_file
    
     File.join(CapistranoMulticonfigParallel.log_directory, "delegator.log")
  end

  def __worker_log
      worker_log = ::Logger.new(__log_file)
      worker_log.level = ::Logger::Severity::DEBUG
    worker_log
  end
  
  def __action
    self.__action
  end
  
   def __action=(val)
    self.__action = val
  end
  
  # Handles the magic of delegation through \_\_getobj\_\_.
  #
  # If *any* of the targets respond to the message, then we send the message to all targets that do
  # respond to it. The return value is an array of the return value from each target method that was
  # invoked.
  #
  # Otherwise (no targets respond), we send it to super.
  #
  def method_missing(message, *args, &block)
    targets = self.__getobj__
    begin
    __worker_log.debug "method_missing #{message}".inspect
      return_values =  targets.map do |target|
        if    __target_selective_delegation?(target)
        target.__send__(message, *args, &block)  if  __target_selective_methd?(target, message)
        else
          target.respond_to?(message) ? target.__send__(message, *args, &block) :   super(message, *args, &block)
        end
      end
      return_values.first
    ensure
      $@.delete_if {|t| %r"\A#{Regexp.quote(__FILE__)}:#{__LINE__-2}:"o =~ t} if $@
    end
  end
  
  
  def __target_selective_methd?(target, message)
      target.selective_delegation_methods(self.__action).include?(message.to_s) && target.method(message.to_s) 
  end
  
    def __target_selective_delegation?(target)
    target.method('selective_delegation_methods').present? 
  end
    
  # TODO:
  #def respond_to_missing?(m, include_private)

  #
  # Returns the methods available to this delegate object as the union
  # of each target's methods and \_\_getobj\_\_ methods.
  #
  def methods
    __getobj__.inject([]) {|array, obj| array | obj.methods } | super
  end

  def public_methods(all=true)
    __getobj__.inject([]) {|array, obj| array | obj.public_methods(all) } | super
  end

  def protected_methods(all=true)
    __getobj__.inject([]) {|array, obj| array | obj.protected_methods(all) } | super
  end

  #
  # Returns true if two objects are considered of equal value.
  #
  def ==(obj)
    return true if obj.equal?(self)
    __getobj__.any? {|_| _ == obj }
  end

  #
  # Returns true if two objects are not considered of equal value.
  #
  def !=(obj)
    return false if obj.equal?(self)
    __getobj__.any? {|_| _ != obj }
  end

  def !
    #!__getobj__
    __getobj__.map {|_| !_ }
  end

  # TODO:
  #def marshal_dump
  #def marshal_load(data)
  #def initialize_clone(obj) # :nodoc:
  #def initialize_dup(obj) # :nodoc:
end

#===================================================================================================


#===================================================================================================

def DelegatorToAll.delegating_block(message)
  lambda do |*args, &block|
    targets = self.__getobj__
    begin
        self.__worker_log.debug "delegating_block #{message}".inspect
      # We loop through targets and use map to make sure we return the return value from all
      # targets.
      targets.map do |target|
        if  self.__target_selective_delegation?(target)
            target.__send__(message, *args, &block)   if  self.__target_selective_methd?(target, message)
        else
          target.__send__(message, *args, &block) 
        end
      end #.tap {|ret_value| puts %(ret_value=#{(ret_value).inspect}) }
      
    ensure
      $@.delete_if {|t| /\A#{Regexp.quote(__FILE__)}:#{__LINE__-2}:/o =~ t} if $@
    end
  end
end

#===================================================================================================

def DelegateToAllClass(superclass)
  klass = Class.new(DelegatorToAll)
  # Delegate all instance methods from superclass to the target objects returned by __getobj__
  methods = superclass.instance_methods
  methods -= ::Delegator.public_api
  methods -= [:to_s,:inspect,:=~,:!~,:===]
  klass.module_eval do
    def __getobj__  # :nodoc:
      @delegate_dc_obj
    end
    def __setobj__(obj)  # :nodoc:
      raise ArgumentError, "cannot delegate to self" if self.equal?(obj)
      @delegate_dc_obj = obj
    end
    #puts %(methods=#{(methods).sort.inspect})
    methods.each do |method|
      define_method(method, DelegatorToAll.delegating_block(method))
    end
  end
  klass.define_singleton_method :public_instance_methods do |all=true|
    super(all) - superclass.protected_instance_methods
  end
  klass.define_singleton_method :protected_instance_methods do |all=true|
    super(all) | superclass.protected_instance_methods
  end
  return klass
end

#===================================================================================================

