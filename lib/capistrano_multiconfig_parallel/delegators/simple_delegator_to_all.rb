require_relative './delegator_to_all'
# This is identical to SimpleDelegator except for its superclass.
class SimpleDelegatorToAll < DelegatorToAll
  # Returns the current object method calls are being delegated to.
  def __getobj__
    @delegate_sd_obj
  end

  #
  # Changes the delegate object to _obj_.
  #
  # It's important to note that this does *not* cause SimpleDelegator's methods
  # to change.  Because of this, you probably only want to change delegation
  # to objects of the same type as the original delegate.
  #
  # Here's an example of changing the delegation object.
  #
  #   names = SimpleDelegator.new(%w{James Edward Gray II})
  #   puts names[1]    # => Edward
  #   names.__setobj__(%w{Gavin Sinclair})
  #   puts names[1]    # => Sinclair
  #
  def __setobj__(obj)
    raise ArgumentError, "cannot delegate to self" if self.equal?(obj)
    @delegate_sd_obj = obj
  end
end
