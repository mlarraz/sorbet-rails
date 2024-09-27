# typed: false
require "rails"
require "sorbet-runtime"
require "sorbet-rails/config"

class SorbetRails::Railtie < Rails::Railtie
  railtie_name "sorbet-rails"

  rake_tasks do
    path = File.expand_path(T.must(__dir__))
    Dir.glob("#{path}/tasks/**/*.rake").each { |f| load f }
  end

  initializer "sorbet-rails.initialize" do
    ActiveSupport.on_load(:active_record) do
      require "sorbet-rails/rails_mixins/custom_finder_methods"
      require "sorbet-rails/rails_mixins/pluck_to_tstruct"

      ActiveRecord::Base.extend SorbetRails::CustomFinderMethods
      ActiveRecord::Relation.include SorbetRails::CustomFinderMethods

      ActiveRecord::Base.extend SorbetRails::PluckToTStruct
      ActiveRecord::Relation.include SorbetRails::PluckToTStruct

      class ::ActiveRecord::Base
        # open ActiveRecord::Base to override inherited
        class << self
          alias_method :sbr_old_inherited, :inherited

          def inherited(child)
            sbr_old_inherited(child)
            # make the relation classes public so that they can be used for sorbet runtime checks
            child.send(:public_constant, :ActiveRecord_Relation)
            child.send(:public_constant, :ActiveRecord_AssociationRelation)
            child.send(:public_constant, :ActiveRecord_Associations_CollectionProxy)

            #### PROOF PATCH
            # We are patching SorbetRails because there is an issue
            # preventing us from using Sorbet's `T.any` with types extending
            # `ActiveRecord::Base`.
            #
            # Explanation
            #
            # In `active_record/relation/delegation.rb` `initialize_relation_delegate_cache`
            # method, ActiveRecord creates classes in each of our models extending
            # `ActiveRecord::Base`. Those classes are used when doing ActiveRecord queries,
            # for example:
            #
            # User.all -> User::ActiveRecord_Relation
            #
            # The class `User::ActiveRecord_Relation` was dynamically defined by
            # `initialize_relation_delegate_cache`. The thing is that classes are defined with:
            #
            #        [
            #           ActiveRecord::Relation,
            #           ActiveRecord::Associations::CollectionProxy,
            #           ActiveRecord::AssociationRelation,
            #           ActiveRecord::DisableJoinsAssociationRelation
            #         ].each do |klass|
            #           delegate = Class.new(klass) {
            #             include ClassSpecificRelation
            #           }
            #
            # and therefore classes' names are just `ActiveRecord::Relation` without the namespace
            # provided by the child class, for example:
            #
            # User::ActiveRecord_Relation.name      -> ActiveRecord::Relation
            # Document::ActiveRecord_Relation.name  -> ActiveRecord::Relation
            #
            # When using those types with Sorbet `T.any`, like:
            #
            # T.any(
            #   User::ActiveRecord_Relation,
            #   Document::ActiveRecord_Relation
            # )
            #
            # Sorbet's `T::Types::Union` will do a `types.uniq` class, which filters
            # them out by `#name` method. Because they have the same name, only the first type
            # is in the union, the second one is removed.
            #
            # Calling `#to_s` on those types returns the full namespace:
            #
            # User::ActiveRecord_Relation.name      -> User::ActiveRecord::Relation
            # Document::ActiveRecord_Relation.name  -> Document::ActiveRecord::Relation
            #
            # So here we are copy/pasting the SorbetRails Railtie defined in:
            # vendor/bundle/ruby/3.0.0/gems/sorbet-rails-0.7.34/lib/sorbet-rails/railtie.rb
            # and applying on monkey patch to redefine `#name` on those classes
            # and delegating to `#to_s`.
            [
              child.const_get(:ActiveRecord_Relation),
              child.const_get(:ActiveRecord_AssociationRelation),
              child.const_get(:ActiveRecord_Associations_CollectionProxy)
            ].each do |klass|
              klass.instance_eval { def name; to_s end }
            end
            #### END PROOF PATCH

            relation_type = T.type_alias do
              T.any(
                child.const_get(:ActiveRecord_Relation),
                child.const_get(:ActiveRecord_AssociationRelation),
                child.const_get(:ActiveRecord_Associations_CollectionProxy)
              )
            end
            child.const_set(:RelationType, relation_type)
            child.send(:public_constant, :RelationType)
          end
        end
      end
    end

    ActiveSupport.on_load(:action_controller) do
      require "sorbet-rails/rails_mixins/generated_url_helpers"
    end

    SorbetRails.register_configured_plugins
  end
end
