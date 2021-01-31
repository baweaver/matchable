# frozen_string_literal: true

RSpec.describe Matchable do
  class Person
    include Matchable

    deconstruct :new
    deconstruct_keys :name, :age

    attr_reader :name, :age

    def initialize(name, age)
      @name = name
      @age  = age
    end
  end

  class Card
    include Matchable

    deconstruct :to_a
    deconstruct_keys :suit, :rank

    attr_reader :suit, :rank

    def initialize(suit, rank)
      @suit = suit
      @rank = rank
    end

    def to_a() = [@suit, @rank]
  end

  class Node
    include Matchable

    deconstruct :to_something_else
    deconstruct_keys :value, :children

    attr_reader :value, :children

    def initialize(value, *children)
      @value    = value
      @children = children
    end

    def to_something_else() = [@value, @children.flat_map(&:to_something_else)]
    def self.[](...) = new(...)
  end

  let(:alice) { Person.new('Alice', 42) }
  let(:ace_of_spades) { Card.new('S', 'A') }
  let(:node) { Node[1, Node[2], Node[3], Node[4, Node[5]]] }

  it "has a version number" do
    expect(Matchable::VERSION).not_to be nil
  end

  describe '#deconstruct' do
    it 'can deconstruct from #new on a class' do
      expect(alice.deconstruct).to eq(['Alice', 42])
      expect((alice in [/^A/, 30..])).to eq(true)
    end

    it 'can deconstruct from a method like #to_a' do
      expect(ace_of_spades.deconstruct).to eq(['S', 'A'])
      expect((ace_of_spades in ['S', _])).to eq(true)
    end

    it 'can deconstruct from any array-like method' do
      expect(node.deconstruct).to eq([
        1, [2, [], 3, [], 4, [5, []]]
      ])

      expect((node in [1, [*, 4, *]])).to eq(true)
    end
  end

  describe '#deconstruct_keys' do
    it 'can deconstruct attributes against all keys' do
      expect(alice.deconstruct_keys(nil)).to eq({
        name: 'Alice',
        age:  42
      })

      expect((alice in {
        name: /^A/,
        age: 30..
      })).to eq(true)
    end

    it 'can deconstruct attributes against a subset of keys' do
      expect(alice.deconstruct_keys([:name])).to eq({
        name: 'Alice'
      })

      expect((alice in {
        name: /^A/
      })).to eq(true)
    end
  end
end
