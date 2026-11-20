require 'test_helper'

module Platform
  # The will_filter subclasses behind the admin screens.
  #
  # These are declarative: each is a handful of methods returning the filter's defaults and the
  # joins its admin list needs.  Running a filter is will_filter's job; what is worth covering
  # here is the declarations, because they name model classes and columns as *strings and
  # symbols* and so nothing checks them until an admin screen is opened.
  #
  # The declarative checks below build their filter with #allocate rather than #new.  They read no
  # state, so skipping the constructor costs nothing, and it keeps them off the database and away
  # from WillFilter::Filter#initialize -- which insists on resolving a model class, something
  # Platform::BaseFilter itself has none for ("Platform::Base" does not exist).
  #
  # The tests that do need a model class use #new, which works now: Platform::Engine used to set
  # will_filter's table_name_prefix `unless Rails.env.test?`, leaving WillFilter::Filter pointed
  # at will_filter_filters under test while the dummy schema -- like production's -- has
  # wf_filters, so no filter could be instantiated in a test at all.
  class BaseFilterTest < Platform::TestCase

    ##########################################################################
    #### BaseFilter
    ##########################################################################

    test 'the default filters are created and updated today' do
      assert_equal [['Created Today', 'created_today'], ['Updated Today', 'updated_today']],
                   filter(Platform::BaseFilter).default_filters
    end

    test 'each default filter key has conditions' do
      base = filter(Platform::BaseFilter)

      base.default_filters.each do |_label, key|
        assert_not_nil base.default_filter_conditions(key), "#{key} should have conditions"
      end
    end

    test 'the default filter conditions name a timestamp column and today' do
      base = filter(Platform::BaseFilter)

      assert_equal [:created_at, :is_on, Date.today], base.default_filter_conditions('created_today')
      assert_equal [:updated_at, :is_on, Date.today], base.default_filter_conditions('updated_today')
    end

    test 'an unknown filter key has no conditions' do
      assert_nil filter(Platform::BaseFilter).default_filter_conditions('not_a_filter')
    end

    test 'the default order is newest first' do
      assert_equal 'created_at', filter(Platform::BaseFilter).default_order
      assert_equal 'desc',       filter(Platform::BaseFilter).default_order_type
    end

    test 'the base class opens with no filter applied' do
      assert_nil filter(Platform::BaseFilter).default_filter_if_empty
    end

    ##########################################################################
    #### The subclasses
    ##########################################################################

    SUBCLASSES = [
      Platform::ApplicationFilter,
      Platform::ApplicationLogFilter,
      Platform::ApplicationMetricFilter,
      Platform::ApplicationScopeFilter,
      Platform::ApplicationUsageMetricFilter,
      Platform::ApplicationUserFilter,
      Platform::DeveloperFilter,
      Platform::ForumMessageFilter,
      Platform::ForumTopicFilter,
      Platform::RatingFilter,
      Platform::RollupLogFilter,
      Platform::ScopeFilter,
    ].freeze

    test 'every filter in the gem is a BaseFilter' do
      SUBCLASSES.each do |klass|
        assert klass < Platform::BaseFilter, "#{klass.name} should inherit the platform defaults"
      end
    end

    test 'every filter inherits the base defaults' do
      SUBCLASSES.each do |klass|
        assert_equal 'created_at', filter(klass).default_order, klass.name
        assert_equal 'desc',       filter(klass).default_order_type, klass.name
        assert_equal 2,            filter(klass).default_filters.size, klass.name
      end
    end

    # A filter that opens on a preset has to name a key the base class has conditions for, or the
    # screen opens on a filter that selects nothing.
    test 'the filters that open on a preset name a key the base class knows' do
      opening_on_today = SUBCLASSES.select { |k| filter(k).default_filter_if_empty }

      assert_equal [
        Platform::ApplicationLogFilter,
        Platform::ApplicationMetricFilter,
        Platform::ApplicationUsageMetricFilter,
        Platform::ApplicationUserFilter,
        Platform::RatingFilter,
        Platform::RollupLogFilter,
      ], opening_on_today

      opening_on_today.each do |klass|
        key = filter(klass).default_filter_if_empty

        assert_equal 'created_today', key, klass.name
        assert_not_nil filter(klass).default_filter_conditions(key),
                       "#{klass.name} opens on a filter key with no conditions"
      end
    end

    ##########################################################################
    #### The declared joins
    ####
    #### Each is [model class name, foreign key column].  Neither half is resolved until an admin
    #### screen runs the filter, so a name that does not resolve or a column that does not exist
    #### sits there unnoticed -- which is what this found two of.
    ##########################################################################

    test 'the application-scoped filters all join the application on application_id' do
      [Platform::ApplicationLogFilter, Platform::ApplicationMetricFilter,
       Platform::ApplicationScopeFilter, Platform::ApplicationUsageMetricFilter,
       Platform::ApplicationUserFilter].each do |klass|
        assert_equal [['Platform::Application', :application_id]], filter(klass).inner_joins, klass.name
      end
    end

    test 'the filters with nothing to join declare no joins' do
      [Platform::DeveloperFilter, Platform::ForumMessageFilter, Platform::ForumTopicFilter,
       Platform::RatingFilter, Platform::RollupLogFilter, Platform::ScopeFilter].each do |klass|
        assert_equal [], filter(klass).inner_joins, klass.name
      end
    end

    # The check that found both of the joins fixed below, and the guard against a third.
    test 'every declared join names a resolvable model and an existing column' do
      broken = []

      SUBCLASSES.each do |klass|
        filtered = klass.name.sub(/Filter\z/, '').constantize

        filter(klass).inner_joins.each do |class_name, foreign_key|
          joined = (class_name.to_s.constantize rescue nil)
          unless joined.is_a?(Class) && joined < ActiveRecord::Base
            broken << "#{klass.name}: #{class_name} is not a model"
          end

          unless filtered.column_names.include?(foreign_key.to_s)
            broken << "#{klass.name}: #{filtered.table_name} has no #{foreign_key} column"
          end
        end
      end

      assert_equal [], broken
    end

    # This named "Platform::Developer", the module rather than the model, and will_filter
    # constantizes the name to build the join -- so the admin application list could not be
    # filtered at all.  Same mistake Platform::ApplicationDeveloper's belongs_to had.
    test 'the application filter joins the developer model' do
      assert_equal [['Platform::Developer::Developer', :developer_id]],
                   filter(Platform::ApplicationFilter).inner_joins
    end

    # platform_rollup_logs has no application_id: a rollup log records one rollup run over an
    # interval, not one per application.  The declaration had been copied from
    # ApplicationMetricFilter, whose table does have the column.
    test 'the rollup log filter declares no application join' do
      assert_equal [], filter(Platform::RollupLogFilter).inner_joins
      assert_equal false, Platform::RollupLog.column_names.include?('application_id'),
                   'which is why there is no join to declare'
    end

    ##########################################################################
    #### The model each filter name resolves to
    ####
    #### WillFilter::Filter#initialize derives the filtered model from the filter's own class
    #### name: it strips "Filter" off and constantizes what is left.  So the name is not just a
    #### label, it is the lookup -- and it is only checked for nil, not for being a model, so a
    #### name that resolves to something which is not a model gets used as one.
    ##########################################################################

    # The invariant that matters, and the one that caught DeveloperFilter: whatever route a
    # filter is built by, the model it ends up filtering has to be a model.
    test 'every filter resolves to the model it filters' do
      SUBCLASSES.each do |klass|
        resolved = klass.new.model_class

        assert resolved.is_a?(Class) && resolved < ActiveRecord::Base,
               "#{klass.name} filters #{resolved.inspect}, which is not a model"
      end
    end

    test 'each filter resolves to the model its name points at' do
      SUBCLASSES.each do |klass|
        expected = klass == Platform::DeveloperFilter ? Platform::Developer::Developer
                                                      : klass.name.sub(/Filter\z/, '').constantize

        assert_equal expected, klass.new.model_class, klass.name
      end
    end

    # The third instance of the Platform::Developer module/class confusion, after
    # Platform::ApplicationDeveloper's belongs_to and Platform::ApplicationFilter's join.  Here
    # the class name *is* the lookup -- WillFilter::Filter#initialize strips "Filter" and
    # constantizes the rest -- and it only checks that the name resolves to something, not that
    # the something is a model.  So this filter has to name its model itself.
    test 'the developer filter filters the developer model' do
      assert_equal Platform::Developer::Developer, Platform::DeveloperFilter.new.model_class
    end

    test 'the developer filter still honours an explicitly passed model' do
      assert_equal Platform::Application,
                   Platform::DeveloperFilter.new(Platform::Application).model_class
    end

    # How will_filter actually builds a filter: Model.filter does `filter_class.new(self)`.  That
    # route never reaches DeveloperFilter's fallback, so it has to keep working too.
    test 'a filter built through Model.filter gets the calling model' do
      filter = Platform::Developer::Developer.filter(params: {}, filter: Platform::DeveloperFilter)

      assert_equal Platform::Developer::Developer, filter.model_class
    end

    # Model.filter is what every admin screen in this gem calls.  will_filter's own engine
    # includes the concern into ::ApplicationRecord -- the host application's base class, which
    # Platform's models do not descend from -- so Platform::Engine has to include it as well.
    test 'Platform models respond to filter' do
      assert_equal true, Platform::ApplicationRecord.respond_to?(:filter)

      [Platform::Application, Platform::ApplicationLog, Platform::Rating,
       Platform::Developer::Developer].each do |model|
        assert_equal true, model.respond_to?(:filter), model.name
      end
    end

private

    # See the class comment: #allocate, not #new.
    def filter(klass)
      klass.allocate
    end

  end # class BaseFilterTest
end # module Platform
