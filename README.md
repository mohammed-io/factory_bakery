# FactoryBakery

Have you ever wanted to generate a model without the need to configure or write extra stuff like Fixtures or Factories?

You've found the right gem!

This gem is inspired by Python's [model-bakery](https://pypi.org/project/model-bakery/) and [factory_bot_rails](https://github.com/thoughtbot/factory_bot_rails). Thanks for them for the development effort and the inspiration!

This gem let you fill a model object with fake data (just like [model-bakery](https://pypi.org/project/model-bakery/)), according to the attribute's data type. By default, it handles the types defined by ActiveRecord.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'factory_bakery', git: 'https://github.com/mohammed-io/factory_bakery.git'
```

And then execute:

    $ bundle install

Or install it yourself as (**Coming soon**):

    $ gem install factory_bakery

## Usage

### Using The Default Generator

Once you install it, you will get 2 global functions `bake` and `bake`.

The first one generates the model without touching the database (i.e. `save`). While the second one updates the record in the database.

The time you want to make a fake model object, you can use:

```ruby
 bake(MODEL_CLASS, {specific_attribute: 'specific_value' })
 # OR
 bake!(MODEL_CLASS, {specific_attribute: 'specific_value' })
```

The `MODEL_CLASS` is the model that you want to fill with fake values. For instance, if you want to fill the `User` with fake data, but with a valid specific email, it can be as following:
```ruby
 bake(User, {email: 'john@example.com' })
 # OR
 bake!(User, {email: 'john@example.com' })
```

Then you should get a result like this:
```ruby
#<User id: nil, email: "john@example.com", first_name: "pw7meuwq16zinefai0qhq8btqg8zqe", last_name: "qthti7af61n5rlvb8njg3ygncmsofz", phone: "vs8e4lpy63sdv6u", address: "agseb6fjt51who6yel0o6h0t7b1ndr3abn7u0yyc">
```

The data is just gebrish at the moment. This how the basic generator works. Which can be extended or improved later.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Todos
* [ ] Write some test
* [ ] Use symbols along with Model classes
* [ ] How to write generators?
* [ ] Support non-active record models?

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/factory_bakery. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/factory_bakery/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the FactoryBakery project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/factory_bakery/blob/master/CODE_OF_CONDUCT.md).
