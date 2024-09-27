# typed: strict
require ('sorbet-rails/model_plugins/base')
class SorbetRails::ModelPlugins::ActiveRecordAttribute < SorbetRails::ModelPlugins::Base

  sig { override.params(root: Parlour::RbiGenerator::Namespace).void }
  def generate(root)
    columns_hash = @model_class.table_exists? ? @model_class.columns_hash : {}
    return unless columns_hash.size > 0

    attribute_module_name = self.model_module_name("GeneratedAttributeMethods")
    attribute_module_rbi = root.create_module(attribute_module_name)

    model_class_rbi = root.create_class(self.model_class_name)
    model_class_rbi.create_include(attribute_module_name)
    model_defined_enums = @model_class.defined_enums

    columns_hash.sort.each do |column_name, column_def|
      if model_defined_enums.has_key?(column_name)
        generate_enum_methods(attribute_module_rbi, column_name, column_def)
      elsif serialization_coder_for_column(column_name)
        next # handled by the ActiveRecordSerializedAttribute plugin
      else
        column_type = type_for_column_def(column_def)
        attribute_module_rbi.create_method(
          column_name.to_s,
          return_type: column_type.to_s,
        )
        attribute_module_rbi.create_method(
          "#{column_name}=",
          parameters: [
            Parameter.new("value", type: value_type_for_attr_writer(column_type))
          ],
          return_type: nil,
        )
      end

      attribute_module_rbi.create_method(
        "#{column_name}?",
        return_type: "T::Boolean",
      )
    end
  end

  sig {
    params(
      attribute_module_rbi:  Parlour::RbiGenerator::Namespace,
      column_name: String,
      column_def: T.untyped,
    ).void
  }
  def generate_enum_methods(
    attribute_module_rbi,
    column_name,
    column_def
  )
    nilable_column = nilable_column?(column_def)
    assignable_type = "T.any(Integer, String, Symbol)"
    assignable_type = "T.nilable(#{assignable_type})" if nilable_column
    return_type = "String"
    return_type = "T.nilable(#{return_type})" if nilable_column

    attribute_module_rbi.create_method(
      column_name.to_s,
      return_type: return_type,
    )
    attribute_module_rbi.create_method(
      "#{column_name}=",
      parameters: [
        Parameter.new("value", type: assignable_type)
      ],
      return_type: nil,
    )
  end

  sig { params(column_type: ColumnType).returns(String) }
  def value_type_for_attr_writer(column_type)
    # it's safe - and convenient - to assign any "time like" object to a time zone
    # aware attribute because Rails will cast it to a `ActiveSupport::TimeWithZone`
    # (so rereading the attribute will always return the `TimeWithZone` type)
    assignable_time_supertypes = [Date, Time, ActiveSupport::TimeWithZone].map(&:to_s)

    type = column_type.base_type
    if type.is_a?(Class)
      if type == ActiveSupport::TimeWithZone
        type = "T.any(#{assignable_time_supertypes.join(', ')})"
      elsif type < Numeric || type == ActiveSupport::Duration
        type = "T.any(Numeric, ActiveSupport::Duration)"
      elsif type == String
        type = "T.any(String, Symbol)"
      end
    end
    ColumnType.new(base_type: type, nilable: column_type.nilable, array_type: column_type.array_type).to_s
  end
end
