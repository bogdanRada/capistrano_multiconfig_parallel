Configurations::StrictConfiguration.class_eval do
  def property_type(property)
    return unless __configurable?(property)
    @__configurable__[property][:type]
  end
end
