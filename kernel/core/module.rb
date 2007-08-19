class Module
  
  ivar_as_index :__ivars__ => 0, :method_table => 1, :method_cache => 2, :name => 3, :constants => 4, :parent => 5
  def method_cache   ; @method_cache ; end
  def constants_table; @constants    ; end
  def parent         ; @parent       ; end
  
  def method_table
    @method_table
  end
  
  def self.new(&prc)
    mod = allocate
    mod.module_eval(&prc) if block_given?
    mod
  end
  
  def to_s
    if @name
      @name.to_s
    else
      super
    end
  end
  
  def find_method_in_hierarchy(sym)
    return @method_table[sym]
  end

  def alias_method(new_name, current_name)
    meth = find_method_in_hierarchy(current_name)
    if meth
      method_table[new_name] = meth
    else
      raise NameError, "undefined method `#{current_name}' for module `#{self.name}'"
    end
  end
  
  def instance_method(name)
    name = name.to_sym
    cur, cm = __find_method(name)
    return UnboundMethod.new(cur, cm) if cm
    thing = self.kind_of?(Class) ? "class" : "module"
    raise NameError, "undefined method `#{name}' for #{thing} #{self}"
  end

  def instance_methods(all=true)
    filter_methods(:public_names, all) | filter_methods(:protected_names, all)
  end

  def public_instance_methods(all=true)
    filter_methods(:public_names, all)
  end
  
  def private_instance_methods(all=true)
    filter_methods(:private_names, all)
  end
  
  def protected_instance_methods(all=true)
    filter_methods(:protected_names, all)
  end
  
  def filter_methods(filter, all)
    names = method_table.__send__(filter)
    # TODO: fix for module when modules can include modules
    return names if self.is_a?(Module)
    unless all or self.is_a?(MetaClass) or self.is_a?(IncludedModule)
      return names
    end
    
    sup = direct_superclass()
    while sup
      names |= sup.method_table.__send__(filter)
      sup = sup.direct_superclass()
    end
    
    return names
  end
  # private :filter_methods
  
  def const_defined?(name)
    name = name.to_s
    hierarchy = name.split('::')
    hierarchy.shift if hierarchy.first == ""
    hierarchy.shift if hierarchy.first == "Object"
    const = self
    until hierarchy.empty?
      const = const.constants_table[hierarchy.shift.to_sym]
      return false unless const
    end
    return true
  end

  def define_method(name, meth = nil, &prc)
    meth ||= prc
    case meth
    when Proc
      block_env = meth.block
      meth_ctx = block_env.home
      cm = meth_ctx.method.dup
      initial = block_env.initial_ip
      last = block_env.last_ip + 1
      trimmed_bytecodes = cm.bytecodes.fetch_bytes(initial, last - initial)
      cm.bytecodes = trimmed_bytecodes
    when Method, UnboundMethod
      cm = meth.instance_eval { @method }
      meth = meth.dup
    when CompiledMethod
      cm = meth
      meth = UnboundMethod.new(self, cm)
    else
      raise TypeError, "invalid argument type #{meth.class} (expected Proc/Method)"
    end
    self.method_table[name.to_sym] = cm
    meth
  end
  
  # Don't call this include, otherwise it will shadow the bootstrap
  # version while core loads (a violation of the core/bootstrap boundry)
  def include_cv(*modules)
    modules.reverse_each do |mod|
      mod.append_features(self)
      mod.included(self)
    end
  end
  
  def set_visibility(meth, vis)
    name = meth.to_sym
    tup = find_method_in_hierarchy(name)
    vis = vis.to_sym
    
    unless tup
      raise NoMethodError, "Unknown method '#{name}' to make private"
    end

    method_table[name] = tup.dup
    if Tuple === tup
      method_table[name][0] = vis
    else
      method_table[name] = Tuple[vis, tup]
    end
    
    return name
  end
  
  # Same as include_cv above, don't call this private.
  def private_cv(*args)
    args.each { |meth| set_visibility(meth, :private) }
  end
  
  def protected(*args)
    args.each { |meth| set_visibility(meth, :protected) }
  end
  
  def public(*args)
    args.each { |meth| set_visibility(meth, :public) }
  end
  
  # A fixup, move the core versions in place now that everything
  # is loaded.
  def self.after_loaded
    alias_method :include, :include_cv
    alias_method :private, :private_cv
  end
  
  
  def module_exec(*args, &prc)
    instance_exec(*args, &prc)
  end
  alias_method :class_exec, :module_exec

  def module_eval(string = nil, filename = "(eval)", lineno = 1, &prc)
    instance_eval(string, filename, lineno, &prc)
  end
  alias_method :class_eval, :module_eval

  # TODO - Handle module_function without args, as per 'private' and 'public'
  def module_function(*method_names)
    if method_names.empty?
      raise ArgumentError, "module_function without an argument is not supported"
    else
      mod_methods = method_table
      inst_methods = metaclass.method_table
      method_names.each do |method_name|
        inst_methods[method_name] = mod_methods[method_name]
      end
    end
    nil
  end
  
  def constants
    constants_table.keys.map { |v| v.to_s }
  end

  def const_set(name, value)
    constants_table[const_name_validate(name)] = value
  end

  def const_get(name)
    constants_table[const_name_validate(name)]
  end
  
  def const_missing(name)
    raise NameError, "Unable to find constant #{name}" 
  end

  def const_name_validate(name)
    raise ArgumentError, "#{name} is not a symbol" if Fixnum === name

    unless name.respond_to?(:to_sym)
      raise TypeError, "#{name} is not a symbol"
    end

    unless name.to_s =~ /^[A-Z]\w*$/
      raise NameError, "wrong constant name #{name}"
    end

    name.to_sym
  end
  private :const_name_validate
end
