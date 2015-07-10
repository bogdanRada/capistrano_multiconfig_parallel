require_relative "../lib/capistrano_multiconfig_parallel/delegators/simple_delegator_to_all"
require_relative "../lib/capistrano_multiconfig_parallel/delegators/tee"
class ExtArray<DelegateToAllClass(Array)
  def initialize()
    super(['a'], ['b'])
  end

  define_method(:to_s, DelegatorToAll.delegating_block(:to_s))
end

ary = ExtArray.new
p ary.class
ary.push 25
# Question: Why does it produce this ugly to_s output if we don't *explicitly* send to_s? ary=#<ExtArray:0x000000010677b8>
puts %(ary=#{(ary)})
puts %(ary=#{(ary.to_s)})
ary.push 42
puts %(ary=#{(ary.to_s)})

#puts %(ary.methods=#{(ary.methods).sort.inspect})

#-------------------------------------------------------------------------------------------------
# SimpleDelegatorToAll test
foo = Object.new
def foo.test
  25
end
def foo.iter
  yield self
end
def foo.error
  raise 'this is OK'
end
foo2 = SimpleDelegatorToAll.new(foo, foo)
p foo2
foo2.instance_eval{print "foo\n"}

puts %(foo == foo2=#{(foo == foo2).inspect}) # => false
puts %(foo2 == foo=#{(foo2 == foo).inspect}) # => true
puts %(foo2 != foo=#{(foo2 != foo).inspect}) # => false

puts %(foo2.test.include? foo.test=#{(foo2.test.include? foo.test).inspect}) # => true
puts %(foo2.iter{[55,true]}=#{(foo2.iter{[55,true]}).inspect}) # => [55,true]
#foo2.error                    # raise error!

false_true_delegator = SimpleDelegatorToAll.new(false, true)
puts %(!false_true_delegator=#{(!false_true_delegator).inspect}) # [true, false]


$stdout = Tee.new(STDOUT, File.open("#{__FILE__}.log", "a"))
$stdout.print("what's? my name")
