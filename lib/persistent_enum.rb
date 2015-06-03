# -*- coding: utf-8 -*-
require "persistent_enum/version"
require "persistent_enum/acts_as_enum"

require "active_support"
require "active_support/inflector"
require "active_record"

# Provide a database-backed enumeration between indices and symbolic
# values. This allows us to have a valid foreign key which behaves like a
# enumeration. Values are cached at startup, and cannot be changed.
module PersistentEnum
  extend ActiveSupport::Concern

  module ClassMethods
    def acts_as_enum(required_constants = [], name_attr: :name)
      include ActsAsEnum
      initialize_acts_as_enum(required_constants, name_attr)
    end

    # Sets up a association with an enumeration record type. Key resolution is
    # done via the enumeration type's cache rather than ActiveRecord. The
    # setter accepts either a model type or the enum constant name as a symbol
    # or string.
    def belongs_to_enum(enum_name, options = {})
      target_class = (options[:class_name] || enum_name.to_s.camelize).constantize
      foreign_key  = options[:foreign_key] || "#{enum_name}_id"

      define_method(enum_name) do
        target_id = read_attribute(foreign_key)
        target_class[target_id]
      end

      define_method("#{enum_name}=") do |enum_member|
        id = case enum_member
             when nil
               nil
             when target_class
               enum_member.ordinal
             else
               m = target_class.value_of(enum_member)
               raise NameError.new("#{target_class.to_s}: Invalid enum constant '#{enum_member}'") if m.nil?
               m.ordinal
             end
        write_attribute(foreign_key, id)
      end

      validates foreign_key, inclusion: { in: ->(r){ target_class.ordinals } }, allow_nil: true
    end
  end

  class << self
    # Given an 'enum-like' table with (id, name) structure and a set of names,
    # ensure that there is a row in the table corresponding to each name, and
    # cache the models as constants on the model class.
    def cache_constants(model, required_constants, name_attr: :name)
      # We need to cope with (a) loading this class and (b) ensuring that all the
      # constants are defined (if not functional) in the case that the database
      # isn't present yet. If no database is present, create dummy values to
      # populate the constants.
      if model.table_exists?
        # Ensure that each of the specified required constants is present
        values = required_constants.map do |rc|
          model.where(name_attr => rc.to_s).first_or_create
        end
      else
        puts "Database table for model #{model.name} doesn't exist, initializing constants with dummy records instead."
        dummyclass = build_dummy_class(model, name_attr)

        next_id = 999999999
        values = required_constants.map do |rc|
          dummyclass.new(next_id += 1, rc.to_s)
        end
      end

      # Set each value as a constant on this class. If reloading, only update if
      # it's changed.
      to_constant_name = ->(s){
        value = s.strip.gsub(/[^\w\s-]/, '').underscore
        return nil if value.blank?
        value.gsub!(/\s+/, '_')
        value.gsub!(/_{2,}/, '_')
        value.upcase!
        value
      }
      values.each do |value|
        constant_name = to_constant_name.call(value.read_attribute(name_attr))
        unless model.const_defined?(constant_name, false) && model.const_get(constant_name, false) == value
          model.const_set(constant_name, value)
        end
      end

      values
    end

    private

    class AbstractDummyModel
      attr_reader :ordinal, :enum_constant

      def initialize(id, name)
        @ordinal = id
        @enum_constant = name
      end

      def to_sym
        enum_constant.to_sym
      end

      alias_method :id, :ordinal

      def read_attribute(attr)
        case attr
        when :id
          ordinal
        when self.class.name_attr
          enum_constant
        else
          nil
        end
      end

      alias_method :[], :read_attribute

      def self.for_name(name_attr)
        Class.new(self) do
          define_singleton_method(:name_attr, ->{name_attr})
          alias_method name_attr, :enum_constant
        end
      end
    end

    def build_dummy_class(model, name_attr)
      if model.const_defined?(:DummyModel, false)
        dummy_class = model::DummyModel
        if dummy_class.superclass == AbstractDummyModel && dummy_class.name_attr == name_attr
          return dummy_class
        else
          model.send(:remove_const, :DummyModel)
        end
      end

      dummy_model = AbstractDummyModel.for_name(name_attr)
      model.const_set(:DummyModel, dummy_model)
    end
  end

  ActiveRecord::Base.send(:include, self)
end
