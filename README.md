# Matchable

Pattern Matching interfaces made easy for Ruby 3.0+

## Usage

`Matchable` works very much like other `-able` interfaces in Ruby:

```ruby
class Something
  include Matchable
end
```

### Basic Example

It exposes two methods, `deconstruct` and `deconstruct_keys`, after the instance methods by the same name which are used as Pattern Matching hooks in Ruby for `Array`-like and `Hash`-like matches:

```ruby
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
```

The above code will generate the following effective code within the `Card` class for you:

```ruby
class Card
  MATCHABLE_KEYS = %i(suit rank)
  MATCHABLE_LAZY_VALUES = {
    suit: -> o { o.suit },
    rank: -> o { o.rank },
  }

  def deconstruct
    to_a
  rescue NameError => e
    raise Matchable::UnmatchedName, e
  end

  def deconstruct_keys(keys)
    if keys.nil?
      return {
        suit: suit,
        rank: rank
      }
    end

    deconstructed_values = {}
    valid_keys           = MATCHABLE_KEYS & keys

    valid_keys.each do |key|
      deconstructed_values[key] = MATCHABLE_LAZY_VALUES[key].call(self)
    end

    deconstructed_values
  rescue NameError => e
    raise Matchable::UnmatchedName, e
  end
end
```

It should be noted that `nil` is passed to `deconstruct_keys` when no values are provided or when a `**rest` pattern is present in the match. In these cases all values should be returned, hence the `if keys.nil?` check.

The generated code is optimized to only include keys which are being directly matched against, guarding against loading more data than is necessary, and all in one line of code above.

In the case of `deconstruct` this method could be anything as long as it returns an `Array`. `to_a` is the most intuitive of these methods, but calling this is not required if you have more unique use-cases.

All calls are wrapped in a `rescue` to `NameError` which will re-raise the error with some additional warnings to warn implementers that they may have forgotten to add some interface methods for Matchable to work properly.

#### Why `MATCHABLE_LAZY_VALUES`?

It's faster than `public_send` and allowed me to unfold one layer of loops. As this type of macro-programming requires pre-evaluation for "compiling" we cannot do something like this, no matter how much I'd like to:

```ruby
valid_keys.each do |key|
  deconstructed_values[key] = ${key}
end
```

While `public_send` works here I'd love to directly interpolate the method call here, hence the faked Macro-style syntax.

### Deconstructing `new`

`Matchable` diverges from more vanilla Ruby in that adding a `deconstruct` against `new` will not alias the method like above, it will treat the constructor itself as the attributes to deconstruct. Consider this `Person` class:

```ruby
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
```

By deconstructing on `new` the following code will be generated for `deconstruct`:

```ruby
class Person
  def deconstruct
    [name, age]
  rescue NameError => e
    raise Matchable::UnmatchedName, e
  end
end
```

These attributes are pulled, as mentioned above, directly from the class constructor. An `attr_reader` or similar method is expected as `Matchable` will not attempt to hunt for instance variables of the same name.

If the parameter names do not match to this requirement it is advised not to use this method with `new`, and instead define your own `deconstruct` method.

As with the above `deconstruct_keys` this method is dynamically generated to directly call methods rather than use `send`-like methods for performance reasons.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'matchable'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install matchable

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/baweaver/matchable. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/baweaver/matchable/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Matchable project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/baweaver/matchable/blob/master/CODE_OF_CONDUCT.md).
