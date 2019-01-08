require 'active_support/core_ext/hash/slice'
require 'protobuf/field/field_array'
require 'protobuf/field/field_hash'
require 'protobuf/field/base_field_method_definitions'

module Protobuf
  module Field
    class BaseField
      include ::Protobuf::Logging
      ::Protobuf::Optionable.inject(self, false) { ::Google::Protobuf::FieldOptions }

      ##
      # Constants
      #

      PACKED_TYPES = [
        ::Protobuf::WireType::VARINT,
        ::Protobuf::WireType::FIXED32,
        ::Protobuf::WireType::FIXED64,
      ].freeze

      ##
      # Attributes
      #
      attr_reader :default_value, :message_class, :name, :fully_qualified_name, :options, :rule, :tag, :type_class

      ##
      # Class Methods
      #

      def self.default
        nil
      end

      ##
      # Constructor
      #

      def initialize(message_class, rule, type_class, fully_qualified_name, tag, simple_name, options)
        @message_class = message_class
        @name = simple_name || fully_qualified_name
        @fully_qualified_name = fully_qualified_name
        @rule          = rule
        @tag           = tag
        @type_class    = type_class
        # Populate the option hash with all the original default field options, for backwards compatibility.
        # However, both default and custom options should ideally be accessed through the Optionable .{get,get!}_option functions.
        @options = options.slice(:ctype, :packed, :deprecated, :lazy, :jstype, :weak, :uninterpreted_option, :default, :extension)
        options.each do |option_name, value|
          set_option(option_name, value)
        end

        @extension = options.key?(:extension)
        @deprecated = options.key?(:deprecated)
        @required = rule == :required
        @repeated = rule == :repeated
        @optional = rule == :optional
        @packed = @repeated && options.key?(:packed)

        validate_packed_field if packed?
        define_accessor(simple_name, fully_qualified_name) if simple_name
        set_repeated_message!
        set_map!
        define_hash_accessor_for_message!
        define_field_p!
        define_field_and_present_p!
        define_set_field!
        define_set_method!
        define_to_message_hash!
        define_encode_to_stream!
        set_default_value!
      end

      ##
      # Public Instance Methods
      #

      def acceptable?(_value)
        true
      end

      def coerce!(value)
        value
      end

      def decode(_bytes)
        fail NotImplementedError, "#{self.class.name}##{__method__}"
      end

      def default
        options[:default]
      end

      def set_default_value!
        @default_value ||= if optional? || required?
                             typed_default_value
                           elsif map?
                             ::Protobuf::Field::FieldHash.new(self).freeze
                           elsif repeated?
                             ::Protobuf::Field::FieldArray.new(self).freeze
                           else
                             fail "Unknown field label -- something went very wrong"
                           end
      end

      def define_encode_to_stream!
        if repeated? && packed?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_repeated_packed_encode_to_stream_method!(self)
        elsif repeated?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_repeated_not_packed_encode_to_stream_method!(self)
        elsif message? || type_class == ::Protobuf::Field::BytesField
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_bytes_encode_to_stream_method!(self)
        elsif type_class == ::Protobuf::Field::StringField
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_string_encode_to_stream_method!(self)
        else
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_base_encode_to_stream_method!(self)
        end
      end

      def define_field_p!
        if repeated?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_repeated_field_p!(self)
        else
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_base_field_p!(self)
        end
      end

      def define_field_and_present_p!
        if type_class == ::Protobuf::Field::BoolField # boolean present check
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_bool_field_and_present_p!(self)
        else
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_base_field_and_present_p!(self)
        end
      end

      def define_hash_accessor_for_message!
        if map?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_map_value_from_values!(self)
        elsif repeated?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_repeated_value_from_values!(self)
        elsif type_class == ::Protobuf::Field::BoolField # boolean present check
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_bool_field_value_from_values!(self)
        else
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_field_value_from_values!(self)
        end
      end

      def define_set_field!
        if map?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_map_set_field!(self)
        elsif repeated?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_repeated_set_field!(self)
        elsif type_class == ::Protobuf::Field::StringField
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_string_set_field!(self)
        else
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_base_set_field!(self)
        end
      end

      def define_to_message_hash!
        if message? || enum? || repeated? || map?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_to_hash_value_to_message_hash!(self)
        else
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_base_to_message_hash!(self)
        end
      end

      def deprecated?
        @deprecated
      end

      def encode(_value)
        fail NotImplementedError, "#{self.class.name}##{__method__}"
      end

      def extension?
        @extension
      end

      def enum?
        false
      end

      def message?
        false
      end

      def set_map!
        set_repeated_message!
        @is_map = repeated_message? && type_class.get_option!(:map_entry)
      end

      def map?
        @is_map
      end

      def optional?
        @optional
      end

      def packed?
        @packed
      end

      def repeated?
        @repeated
      end

      def set_repeated_message!
        @repeated_message = repeated? && message?
      end

      def repeated_message?
        @repeated_message
      end

      def required?
        @required
      end

      def define_set_method!
        if map?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_map_set_method!(self)
        elsif repeated? && packed?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_repeated_packed_set_method!(self)
        elsif repeated?
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_repeated_not_packed_set_method!(self)
        else
          ::Protobuf::Field::BaseFieldMethodDefinitions.define_base_set_method!(self)
        end
      end

      def tag_encoded
        @tag_encoded ||= begin
                           case
                           when repeated? && packed?
                             ::Protobuf::Field::VarintField.encode((tag << 3) | ::Protobuf::WireType::LENGTH_DELIMITED)
                           else
                             ::Protobuf::Field::VarintField.encode((tag << 3) | wire_type)
                           end
                         end
      end

      # FIXME: add packed, deprecated, extension options to to_s output
      def to_s
        "#{rule} #{type_class} #{name} = #{tag} #{default ? "[default=#{default.inspect}]" : ''}"
      end

      ::Protobuf.deprecator.define_deprecated_methods(self, :type => :type_class)

      def wire_type
        ::Protobuf::WireType::VARINT
      end

      def fully_qualified_name_only!
        @name = @fully_qualified_name

        ##
        # Recreate all of the meta methods as they may have used the original `name` value
        #
        define_hash_accessor_for_message!
        define_field_p!
        define_field_and_present_p!
        define_set_field!
        define_set_method!
        define_to_message_hash!
        define_encode_to_stream!
      end

      private

      ##
      # Private Instance Methods
      #

      def define_accessor(simple_field_name, fully_qualified_field_name)
        message_class.class_eval do
          define_method("#{simple_field_name}!") do
            @values[fully_qualified_field_name] if field?(fully_qualified_field_name)
          end
        end

        message_class.class_eval do
          define_method(simple_field_name) { self[fully_qualified_field_name] }
          define_method("#{simple_field_name}=") { |v| set_field(fully_qualified_field_name, v, false) }
        end

        return unless deprecated?

        ::Protobuf.field_deprecator.deprecate_method(message_class, simple_field_name)
        ::Protobuf.field_deprecator.deprecate_method(message_class, "#{simple_field_name}!")
        ::Protobuf.field_deprecator.deprecate_method(message_class, "#{simple_field_name}=")
      end

      def typed_default_value
        if default.nil?
          self.class.default
        else
          default
        end
      end

      def validate_packed_field
        if packed? && ! ::Protobuf::Field::BaseField::PACKED_TYPES.include?(wire_type)
          fail "Can't use packed encoding for '#{type_class}' type"
        end
      end
    end
  end
end
