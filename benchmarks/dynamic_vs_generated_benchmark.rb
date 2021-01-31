#!/usr/bin/env ruby -W0

require 'matchable'
require 'benchmark/ips'

class PersonMacro
  include Matchable

  deconstruct :new
  deconstruct_keys :name, :age

  attr_reader :name, :age

  def initialize(name, age)
    @name = name
    @age  = age
  end
end

class PersonDynamic
  VALID_KEYS = %i(name age)

  attr_reader :name, :age

  def initialize(name, age)
    @name = name
    @age  = age
  end

  def deconstruct() = VALID_KEYS.map { public_send(_1) }

  def deconstruct_keys(keys)
    valid_keys = keys ? VALID_KEYS & keys : VALID_KEYS
    valid_keys.to_h { [_1, public_send(_1)] }
  end
end

alice_macro = PersonMacro.new('Alice', 42)
alice_dynamic = PersonDynamic.new('Alice', 42)

Benchmark.ips do |x|
  x.report("[Person] Macro Generated - Full Hash") do
    alice_macro in { name: /^A/, age: 30.. }
  end

  x.report("[Person] Macro Generated - Partial Hash") do
    alice_macro in { name: /^A/ }
  end

  x.report("[Person] Macro Generated - Array") do
    alice_macro in [/^A/, 30..]
  end

  x.report("[Person] Dynamic Generated - Full Hash") do
    alice_dynamic in { name: /^A/, age: 30.. }
  end

  x.report("[Person] Dynamic Generated - Partial Hash") do
    alice_dynamic in { name: /^A/ }
  end

  x.report("[Person] Dynamic Generated - Array") do
    alice_dynamic in [/^A/, 30..]
  end
end

puts '', '-' * 80, ''

# 26 attributes, should be enough to stress things out
LETTERS = ('a'..'z').to_a.map(&:to_sym)
LETTER_IVARS = LETTERS.map { "@#{_1} = #{_1}" }.join("\n")
LETTER_VALUES = LETTERS.each_with_index.to_h

# Easier than typing 26 attrs
eval <<~RUBY
  class BigAttrMacro
    include Matchable

    deconstruct :new
    deconstruct_keys *LETTERS

    attr_reader *LETTERS

    def initialize(#{LETTERS.join(', ')})
      #{LETTER_IVARS}
    end
  end
RUBY

eval <<~RUBY
  class BigAttrDynamic
    VALID_KEYS = LETTERS

    attr_reader *LETTERS

    def initialize(#{LETTERS.join(', ')})
      #{LETTER_IVARS}
    end

    def deconstruct() = VALID_KEYS.map { public_send(_1) }

    def deconstruct_keys(keys)
      valid_keys = keys ? VALID_KEYS & keys : VALID_KEYS
      valid_keys.to_h { [_1, public_send(_1)] }
    end
  end
RUBY

big_attr_macro   = BigAttrMacro.new(*1..26)
big_attr_dynamic = BigAttrDynamic.new(*1..26)

Benchmark.ips do |x|
  x.report("[BigAttr] Macro Generated - Full Hash") do
    big_attr_macro in {}
  end

  x.report("[BigAttr] Macro Generated - Partial Hash") do
    big_attr_macro in { a:, b:, c:, d:, e:, f: }
  end

  x.report("[BigAttr] Macro Generated - Array") do
    big_attr_macro in [1, 2, 3, *]
  end

  x.report("[BigAttr] Dynamic Generated - Full Hash") do
    big_attr_dynamic in {}
  end

  x.report("[BigAttr] Dynamic Generated - Partial Hash") do
    big_attr_dynamic in { a:, b:, c:, d:, e:, f: }
  end

  x.report("[BigAttr] Dynamic Generated - Array") do
    big_attr_dynamic in [1, 2, 3, *]
  end
end
