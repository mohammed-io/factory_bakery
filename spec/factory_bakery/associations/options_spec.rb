# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Public-API behavior for the full option surface of `association` (A10).
# Everything is asserted through define/bake/bake! or the plugin's public API.
RSpec.describe 'association options' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.reset_configuration!
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  def define_author_and_post(name = 'AssocOpt')
    author = define_model("#{name}Author", name: :string, role: :string, level: :integer)
    post = define_model("#{name}Post", author_id: :integer) do
      belongs_to :author, class_name: "#{name}Author", optional: false
    end
    [author, post]
  end

  def register_editor(author)
    FactoryBakery.define(:assoc_opt_editor, klass: author) do
      role { 'editor' }
      trait(:senior) { level { 3 } }
    end
  end

  describe 'traits on the child' do
    it 'forwards a trait to the child bake so its declarations apply' do
      author, post = define_author_and_post('AssocTraitChild')
      FactoryBakery.define(author) do
        level { 1 }
        trait(:senior) { level { 3 } }
      end
      FactoryBakery.define(post) { association :author, :senior }

      expect(FactoryBakery.bake(post).author.level).to eq(3)
    end

    it 'forwards several traits in declaration order' do
      author, post = define_author_and_post('AssocTraitsChild')
      FactoryBakery.define(author) do
        trait(:one) { level { 1 } }
        trait(:two) { level { 2 } }
      end
      FactoryBakery.define(post) { association :author, :one, :two }

      expect(FactoryBakery.bake(post).author.level).to eq(2)
    end
  end

  describe 'positional target class' do
    it "bakes the target through the class's definition" do
      author, post = define_author_and_post('AssocPositional')
      FactoryBakery.define(author) { role { 'positional' } }
      FactoryBakery.define(post) { association :author, author }

      expect(FactoryBakery.bake(post).author.role).to eq('positional')
    end

    it 'accepts traits and overrides after the class' do
      author, post = define_author_and_post('AssocPositionalTraits')
      FactoryBakery.define(author) { trait(:senior) { level { 3 } } }
      FactoryBakery.define(post) { association :author, author, :senior, name: 'Ann' }

      child = FactoryBakery.bake(post).author
      expect([child.level, child.name]).to eq([3, 'Ann'])
    end

    it 'persists the target with bake!' do
      author, post = define_author_and_post('AssocPositionalPersist')
      FactoryBakery.define(post) { association :author, author }

      expect(FactoryBakery.bake!(post).author).to be_persisted
    end

    it 'names the target of a polymorphic belongs_to' do
      post_model = define_model('AssocPositionalPolyPost', title: :string)
      comment_model = define_model('AssocPositionalPolyComment', commentable_type: :string, commentable_id: :integer) do
        belongs_to :commentable, polymorphic: true, optional: false
      end
      FactoryBakery.define(comment_model) { association :commentable, post_model }

      expect(FactoryBakery.bake(comment_model).commentable).to be_a(post_model)
    end

    it 'rejects a class given both positionally and as factory:' do
      author, post = define_author_and_post('AssocPositionalBoth')

      FactoryBakery.define(post) { association :author, author, factory: author }

      expect { FactoryBakery.bake(post) }.to raise_error(ArgumentError, /positionally or as factory:/)
    end
  end

  describe 'factory:' do
    it 'uses a registered symbol factory and its declarations for the target' do
      author, post = define_author_and_post('AssocSymbolFactory')
      register_editor(author)
      FactoryBakery.define(post) { association :author, factory: :assoc_opt_editor }

      child = FactoryBakery.bake(post).author
      expect([child.class, child.role]).to eq([author, 'editor'])
    end

    it 'accepts a class as the factory target' do
      author, post = define_author_and_post('AssocClassFactory')
      FactoryBakery.define(author) { role { 'from-class-factory' } }
      FactoryBakery.define(post) { association :author, factory: author }

      expect(FactoryBakery.bake(post).author.role).to eq('from-class-factory')
    end

    it 'accepts a subclass of the reflection class' do
      author, post = define_author_and_post('AssocSubclassFactory')
      subclass = define_class('AssocSubclassFactoryEditor', author)
      FactoryBakery.define(subclass) { role { 'subclass' } }
      FactoryBakery.define(post) { association :author, factory: subclass }

      expect(FactoryBakery.bake(post).author).to be_a(subclass)
    end

    it 'raises when the factory target is incompatible with the reflection' do
      _author, post = define_author_and_post('AssocBadFactory')
      other = define_model('AssocBadFactoryOther', name: :string)
      FactoryBakery.define(post) { association :author, factory: other }

      expect { FactoryBakery.bake(post) }
        .to raise_error(FactoryBakery::Error, /factory:.*incompatible/)
    end
  end

  describe 'overrides on the child' do
    it 'forwards overrides and lets them beat the child factory declarations' do
      author, post = define_author_and_post('AssocOverrideChild')
      FactoryBakery.define(author) { name { 'from-factory' } }
      FactoryBakery.define(post) { association :author, name: 'from-association' }

      expect(FactoryBakery.bake(post).author.name).to eq('from-association')
    end

    it 'combines traits, factory: and overrides end to end' do
      author, post = define_author_and_post('AssocCombined')
      register_editor(author)
      FactoryBakery.define(post) do
        association :author, :senior, factory: :assoc_opt_editor, name: 'Ann'
      end

      child = FactoryBakery.bake(post).author
      expect([child.class, child.role, child.level, child.name])
        .to eq([author, 'editor', 3, 'Ann'])
    end
  end

  describe 'precedence' do
    it 'lets a later trait redeclaration replace the base association' do
      author, post = define_author_and_post('AssocRedeclare')
      register_editor(author)
      FactoryBakery.define(post) do
        association :author, :senior, factory: :assoc_opt_editor, name: 'Ann'
        trait(:guest) { association :author, name: 'Guest' }
      end

      expect(FactoryBakery.bake(post).author.name).to eq('Ann')
      expect(FactoryBakery.bake(post, :guest).author.name).to eq('Guest')
    end

    it 'lets a call-site association object beat the declaration and the trait' do
      author, post = define_author_and_post('AssocWinObject')
      register_editor(author)
      FactoryBakery.define(post) do
        association :author, factory: :assoc_opt_editor, name: 'Ann'
        trait(:guest) { association :author, name: 'Guest' }
      end
      chosen = author.create!(name: 'Chosen')

      expect(FactoryBakery.bake(post, :guest, author: chosen).author).to equal(chosen)
      expect(author.count).to eq(1)
    end

    it 'lets a call-site foreign key beat the declaration' do
      author, post = define_author_and_post('AssocWinFk')
      register_editor(author)
      FactoryBakery.define(post) { association :author, factory: :assoc_opt_editor, name: 'Ann' }
      chosen = author.create!(name: 'Chosen')

      baked = FactoryBakery.bake(post, author_id: chosen.id)
      expect(baked.author_id).to eq(chosen.id)
      expect(author.count).to eq(1)
    end
  end

  describe 'polymorphic targets' do
    def define_comment(name)
      define_model("#{name}Post", title: :string)
      define_model("#{name}Comment", body: :string, commentable_type: :string, commentable_id: :integer) do
        belongs_to :commentable, polymorphic: true, optional: false
      end
    end

    it 'sets a consistent type/id pair and persists the target under bake!' do
      comment_model = define_comment('AssocPoly')
      post_model = Object.const_get('AssocPolyPost')
      FactoryBakery.define(comment_model) { association :commentable, factory: post_model }

      comment = FactoryBakery.bake!(comment_model)

      expect(comment.commentable).to be_a(post_model)
      expect(comment.commentable_type).to eq(post_model.polymorphic_name)
      expect(comment.commentable_id).to eq(comment.commentable.id)
      expect(comment.commentable.persisted?).to be(true)
    end

    it 'stores the base polymorphic name for an STI subclass target' do
      base = define_model('AssocPolyStiVehicle', name: :string, type: :string)
      subclass = define_class('AssocPolyStiCar', base)
      comment_model = define_model(
        'AssocPolyStiRide', commentable_type: :string, commentable_id: :integer
      ) do
        belongs_to :commentable, polymorphic: true, optional: false
      end
      FactoryBakery.define(comment_model) { association :commentable, factory: subclass }

      comment = FactoryBakery.bake(comment_model)

      expect(comment.commentable).to be_a(subclass)
      expect(comment.commentable_type).to eq(subclass.polymorphic_name)
      expect(comment.commentable_type).to eq(base.name)
    end

    it 'forwards traits and overrides to a symbol factory target' do
      post_model = define_model('AssocPolySymbolPost', title: :string)
      comment_model = define_model(
        'AssocPolySymbolComment', commentable_type: :string, commentable_id: :integer
      ) do
        belongs_to :commentable, polymorphic: true, optional: false
      end
      FactoryBakery.define(:assoc_poly_symbol_post, klass: post_model) { title { 'from factory' } }
      FactoryBakery.define(comment_model) do
        association :commentable, factory: :assoc_poly_symbol_post, title: 'from association'
      end

      comment = FactoryBakery.bake(comment_model)

      expect(comment.commentable.title).to eq('from association')
      expect(comment.commentable_type).to eq(post_model.polymorphic_name)
    end

    it 'raises an actionable error when factory: is missing' do
      comment_model = define_comment('AssocPolyNoFactory')
      FactoryBakery.define(comment_model) { association :commentable }

      expect { FactoryBakery.bake(comment_model) }
        .to raise_error(FactoryBakery::Error, /polymorphic.*commentable.*factory:/)
    end

    it 'lets a call-site override suppress a polymorphic declaration without factory:' do
      comment_model = define_comment('AssocPolyOverride')
      post_model = Object.const_get('AssocPolyOverridePost')
      FactoryBakery.define(comment_model) { association :commentable }
      chosen = post_model.create!(title: 'chosen')

      comment = FactoryBakery.bake(comment_model, commentable: chosen)

      expect(comment.commentable).to equal(chosen)
      expect(comment.commentable_type).to eq(post_model.polymorphic_name)
    end
  end

  describe 'several declarations on one owner' do
    it 'builds each association with its own options' do
      person = define_model('AssocMultiPerson', name: :string)
      post = define_model('AssocMultiPost', author_id: :integer, editor_id: :integer) do
        belongs_to :author, class_name: 'AssocMultiPerson', optional: false
        belongs_to :editor, class_name: 'AssocMultiPerson', optional: false
      end
      FactoryBakery.define(post) do
        association :author, name: 'Author'
        association :editor, name: 'Editor'
      end

      baked = FactoryBakery.bake(post)

      expect([baked.author.name, baked.editor.name]).to eq(%w[Author Editor])
      expect(person.count).to eq(0)
    end
  end

  describe 'bake! persistence contract' do
    it 'persists a target configured with traits, factory: and overrides' do
      author, post = define_author_and_post('AssocBangOptions')
      register_editor(author)
      FactoryBakery.define(post) do
        association :author, :senior, factory: :assoc_opt_editor, name: 'Persisted'
      end

      baked = FactoryBakery.bake!(post)

      expect([baked.persisted?, baked.author.persisted?, baked.author_id == baked.author.id])
        .to eq([true, true, true])
      expect(baked.author.name).to eq('Persisted')
      expect(author.count).to eq(1)
      expect(post.count).to eq(1)
    end
  end

  describe 'depth backstop' do
    it 'raises when recursive association declarations build past the depth limit' do
      define_model('AssocDeepA', b_id: :integer) do
        belongs_to :b, class_name: 'AssocDeepB', optional: false
      end
      define_model('AssocDeepB', a_id: :integer) do
        belongs_to :a, class_name: 'AssocDeepA', optional: false
      end
      a_model = Object.const_get('AssocDeepA')
      b_model = Object.const_get('AssocDeepB')
      FactoryBakery.define(a_model) { association :b }
      FactoryBakery.define(b_model) { association :a }

      expect { FactoryBakery.bake(a_model) }
        .to raise_error(FactoryBakery::NestingTooDeepError, /max_bake_depth/)
    end
  end

  describe 'unsupported options' do
    it 'accepts an explicit strategy: :reuse_non_unique on a belongs_to' do
      author, post = define_author_and_post('AssocStrategyReuse')
      existing = author.create!(name: 'existing')
      FactoryBakery.define(post) { association :author, strategy: :reuse_non_unique }

      expect(FactoryBakery.bake(post).author).to eq(existing)
    end

    it 'rejects count: on a singular association now that collections support it' do
      _author, post = define_author_and_post('AssocCountGuard')
      FactoryBakery.define(post) { association :author, count: 2 }

      expect { FactoryBakery.bake(post) }
        .to raise_error(ArgumentError, /count:.*collection/)
    end
  end

  describe 'block form' do
    it 'passes the owner to the block and assigns its return value' do
      author_model = define_model('AssocBlockFormAuthor', name: :string)
      post_model = define_model('AssocBlockFormPost', author_id: :integer, title: :string) do
        belongs_to :author, class_name: 'AssocBlockFormAuthor', optional: true
      end
      FactoryBakery.define(post_model) do
        association(:author) { |owner| FactoryBakery.bake(author_model, name: owner.title) }
      end

      baked = FactoryBakery.bake(post_model, title: 'owner title')

      expect(baked.author.name).to eq('owner title')
    end
  end
end
