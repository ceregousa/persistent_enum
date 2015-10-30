# -*- coding: utf-8 -*-

require "bundler/setup"
puts Bundler.require

require "minitest/autorun"

class PersistentEnumTest < ActiveSupport::TestCase
  ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"

  CONSTANTS = [:One, :Two, :Three, :Four]

  def setup
    # Horrible horrible hack: temporary tables don't show up in SHOW TABLES
    # LIKE, which the mysql driver uses for table_exists?. Non-temporary tables
    # break the test runner's transactions. This test requires table_exists? to
    # function. So override table_exists? to first check a list of temporary
    # tables.
    @temporary_tables = tt = Set.new
    ActiveRecord::Base.connection.define_singleton_method(:table_exists?){ |name| tt.include?(name) || super(name) }

    create_test_model(:test_persistent_enum, ->(t){ t.string :name }) do
      acts_as_enum(CONSTANTS)
    end

    create_test_model(:test_belongs_to_enum, ->(t){ t.integer :test_persistent_enum_id }) do
      belongs_to_enum :test_persistent_enum
    end

    create_test_model(:test_persistent_enum_without_table, nil, create_table: false) do
      acts_as_enum(CONSTANTS)
    end
  end

  def teardown
    destroy_test_model(:test_persistent_enum)
    destroy_test_model(:test_belongs_to_enum)
    destroy_test_model(:test_persistent_enum_without_table)

    ActiveRecord::Base.connection.singleton_class.send(:remove_method, :table_exists?)
    @temporary_tables = nil
  end

  def test_enum_lookup
    [TestPersistentEnum, TestPersistentEnumWithoutTable].each do |table|
      CONSTANTS.each do |c|
        e = table.value_of(c)
        assert(e.present?)
        assert(e.enum_constant.is_a?(String))
        assert_equal(e.to_sym, c)
        assert_equal(e, table[e.ordinal])
        assert_equal(e, table.const_get(c.upcase))
      end
    end
  end

  def test_enum_values
    expected = Set.new(CONSTANTS)
    # Cached
    assert_equal(expected, Set.new(TestPersistentEnum.values.map(&:to_sym)))
    # And stored
    assert_equal(expected, Set.new(TestPersistentEnum.all.map(&:to_sym)))
  end

  def test_existing_data
    create_test_model(:test_existing, ->(t){ t.string :name }) do
      create(name: CONSTANTS.first.to_s)
      create(name: "Hello") # Not one of the constants
      acts_as_enum(CONSTANTS)
    end

    # test names/values
    expected_all = (CONSTANTS + [:Hello]).sort
    expected_required = CONSTANTS.sort

    assert_equal(expected_required, TestExisting.values.map(&:to_sym).sort)

    assert_equal(expected_all,      TestExisting.all_values.map(&:to_sym).sort)
    assert_equal(expected_all,      TestExisting.all.map(&:to_sym).sort)

    # test ordinals
    expected_required = expected_required.map { |name| TestExisting.value_of!(name).ordinal }.sort
    expected_all      = expected_all.map { |name| TestExisting.value_of!(name).ordinal }.sort

    assert_equal(expected_required, TestExisting.ordinals.sort)
    assert_equal(expected_all, TestExisting.all_ordinals.sort)
    assert_equal(expected_all, TestExisting.pluck(:id).sort)

    # Should be able to look up existing value by id or name
    existing_value = TestExisting.where(name: "Hello").first
    assert_equal(existing_value, TestExisting[existing_value.ordinal])
    assert_equal(existing_value, TestExisting.value_of(existing_value.enum_constant))

    destroy_test_model(:test_existing)
  end

  def test_requires_constants
    create_test_model(:test_requires_constant, ->(t){ t.string :name }) do
      PersistentEnum.cache_constants(self, CONSTANTS)
    end

    CONSTANTS.each do |c|
      cached = TestRequiresConstant.const_get(c.upcase)
      assert(cached.present?)
      assert_equal(c.to_s, cached.name)
      stored = TestRequiresConstant.where(name: c.to_s).first
      assert(stored.present?)
      assert_equal(cached, stored)
    end

    destroy_test_model(:test_requires_constant)
  end

  def test_constant_naming
    test_constants = {
      "CamelCase"             => "CAMEL_CASE",
      :Symbolic               => "SYMBOLIC",
      "with.punctuation"      => "WITH_PUNCTUATION",
      "multiple_.underscores" => "MULTIPLE_UNDERSCORES"
    }

    create_test_model(:test_constant_name, ->(t){ t.string :name }) do
      PersistentEnum.cache_constants(self, test_constants.keys)
    end

    test_constants.each do |k, v|
      assert(TestConstantName.const_get(v).present?)
    end

    destroy_test_model(:test_constant_name)
  end

  def test_enum_immutable
    assert_raises(ActiveRecord::ReadOnlyRecord) do
      TestPersistentEnum.create(name: "foo")
    end

    assert_raises(RuntimeError) do # frozen object
      TestPersistentEnum::ONE.name = "foo"
    end

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      TestPersistentEnum.first.update_attribute(:name, "foo")
    end

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      TestPersistentEnum.first.destroy
    end
  end

  def test_belongs_to_enum
    CONSTANTS.each do |c|
      e = TestPersistentEnum.value_of(c)

      # Should be able to create from enum value or constant
      [c, e].each do |arg|
        t = TestBelongsToEnum.new(test_persistent_enum: c)
        assert(t.valid?)
        assert_equal(t.test_persistent_enum, e)
        assert_equal(t.test_persistent_enum_id, e.ordinal)
      end

      # Should be able to create by foreign key
      t = TestBelongsToEnum.new(test_persistent_enum_id: e.ordinal)
      assert(t.valid?)
      assert_equal(t.test_persistent_enum, e)
    end

    # Should be able to create null
    t = TestBelongsToEnum.new
    assert(t.valid?)

    # but not with an invalid foreign key
    t = TestBelongsToEnum.new(test_persistent_enum_id: -1)
    assert(!t.valid?)

    # or with a constant that's not a member of the enum
    assert_raises(NameError) do
      TestBelongsToEnum.new(test_persistent_enum: :BadConstant)
    end
  end

private

  def create_test_model(name, columns, create_table: true, &block)
    if create_table
      table_name = name.to_s.pluralize
      ActiveRecord::Base.connection.create_table(table_name, :temporary => true, &columns)
      @temporary_tables << table_name
    end

    model_name = name.to_s.classify
    clazz = Class.new(ActiveRecord::Base)
    Object.const_set(model_name, clazz)
    clazz.primary_key = :id
    clazz.class_eval(&block) if block_given?
    clazz
  end

  def destroy_test_model(name)
    model_name = name.to_s.classify
    clazz = Object.const_get(model_name)
    if !clazz.nil?
      table_name = clazz.table_name
      if clazz.table_exists?
        clazz.connection.drop_table(table_name)
        @temporary_tables.delete(table_name)
      end
      Object.send(:remove_const, model_name)
    end
  end


end
