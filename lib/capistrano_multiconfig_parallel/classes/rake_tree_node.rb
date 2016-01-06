module CapistranoMulticonfigParallel
  # the rake tree node
  class RakeTreeNode < Tree::TreeNode
    def task_node(task, options = {})
      node = options.fetch('root', root)
      task = task.is_a?(Rake::Task) ? task.name : task
      task_node = nil
      node.each do |node|
        if node.name == task || (options[:scoped] == true && node.name == task.split(':')[0])
          task_node = node if task_node.nil?
        end
        task_node = task_node.blank? ? node_contains_hook?(node, 'before', task, options) : task_node
        task_node = task_node.blank? ? node_contains_hook?(node, 'after', task, options) : task_node
      end
      task_node
    end

    def node_contains_hook?(node, hook_name, hook, options = {})
      hook = hook.is_a?(Rake::Task) ? hook.name : hook
      task_node = nil
      if node.content.present? && node.content.is_a?(Hash) && node.content[hook_name].present?
        node.content[hook_name].each do|node|
          if node.name == hook || (options[:scoped] == true && node.name == hook.split(':')[0] || task_node(hook, 'root' => node).present?)
            task_node = node
          end
        end
      end
      task_node
    end

    def get_task_invocation_chain(app, stage, action)
      app_node = app.present? ? task_node("#{app}:#{stage}") : task_node(stage)
      task_node = task_node(action)

      paths = []
      if app_node.present? && task_node.present?
      [app_node, task_node].each do |node|
        get_node_chains(paths, node.parentage)
        #    node.parentage.select  {|child_node|  !child_node.is_root?   }.map { |child_node| get_node_chain(paths, child_node)  }

        get_node_chains(paths, node.each)
        # paths  = node.each.select  {|child_node|  !child_node.is_root?   }.map { |child_node| get_node_chain(paths, child_node)  }
      end
    end
      paths
    end

    def get_node_chains(paths, node)
      node.select { |child_node| !child_node.is_root? }.map { |child_node| get_node_chain(paths, child_node) }
    end

    def get_node_chain(paths, node)
      child_nodes = node.select { |child_node| child_node.content.present? }
      get_node_hook_chain(paths, child_nodes, 'before')
      paths << node.name
      get_node_hook_chain(paths, child_nodes, 'after')
    end

    def get_node_hook_chain(paths, nodes, hook_name)
      nodes.select { |child_node| child_node.content[hook_name].present? }.each do |child_node|
        child_node.content[hook_name].each { |child_content| paths << child_content.name unless child_content.is_root? }
      end
    rescue => e
      raise [e, paths, hook_name].inspect
    end

    def print_tree(level = 0, max_depth = nil, block = ->(node, prefix) { puts "#{prefix} #{node.respond_to?(:name) ? node.name : node}" })
      prefix = fetch_prefix_for_printing(level)
      block.call(self, prefix)
      print_content('before', level, max_depth, block)
      print_content('after', level, max_depth, block)
      return unless max_depth.nil? || level < max_depth # Exit if the max level is defined, and reached.

      children { |child| child.print_tree(level + 1, max_depth, block) if child } # Child might be 'nil'
    end

    def fetch_prefix_for_printing(level)
      prefix = ''
      if is_root?
        prefix << '*'
      else
        prefix << '|' unless parent.is_last_sibling?
        prefix << (' ' * (level - 1) * 4)
        prefix << (is_last_sibling? ? '+' : '|')
        prefix << '---'
        prefix << (has_children? ? '+' : '>')
      end
      prefix
    end

    def print_content(hook_name, level, max_depth, block)
      if content[hook_name].present?
        level += 1
        prefix = fetch_prefix_for_printing(level)
        block.call(hook_name.upcase, prefix) if content[hook_name].has_children?

        content[hook_name].each do |child_content|
          child_content.children { |child| child.print_tree(level + 1, max_depth, block) if child }
        end
      end
    end
  end
end
