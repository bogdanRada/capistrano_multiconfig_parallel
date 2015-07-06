# require_relative '../helpers/extension_helper'
# IO.class_eval do
# 	alias_method :old_gets, :gets

# 	def gets
# 		if CapistranoMulticonfigParallel::ExtensionHelper.inside_job?
# 				CapistranoMulticonfigParallel::ExtensionHelper.run_stdin_actor
# 		else
# 			old_gets
# 		end
# 	end
# end
