module ValueSemantics
  #
  # All the instance methods available on ValueSemantics objects
  #
  module InstanceMethods
    #
    # Creates a value object based on a hash of attributes
    #
    # @param attributes [#to_h] A hash of attribute values by name. Typically a
    #   +Hash+, but can be any object that responds to +#to_h+.
    #
    # @raise [UnrecognizedAttributes] if given_attrs contains keys that are not
    #   attributes
    # @raise [MissingAttributes] if given_attrs is missing any attributes that
    #   do not have defaults
    # @raise [InvalidValue] if any attribute values do no pass their validators
    # @raise [TypeError] if the argument does not respond to +#to_h+
    #
    def initialize(attributes = nil)
      attributes_hash =
        if attributes.respond_to?(:to_h)
          attributes.to_h
        else
          raise TypeError, <<-END_MESSAGE.strip.gsub(/\s+/, ' ')
            Can not initialize a `#{self.class}` with a `#{attributes.class}`
            object. This argument is typically a `Hash` of attributes, but can
            be any object that responds to `#to_h`.
          END_MESSAGE
        end

      remaining_attrs = attributes_hash.keys
      missing_attrs = nil
      invalid_attrs = nil

      self.class.value_semantics.attributes.each do |attr|
        if remaining_attrs.delete(attr.name)
          value = attributes_hash.fetch(attr.name)
        elsif attr.optional?
          value = attr.default_generator.()
        else
          missing_attrs ||= []
          missing_attrs << attr.name
          next
        end

        coerced_value = attr.coerce(value, self.class)
        if attr.validate?(coerced_value)
          instance_variable_set(attr.instance_variable, coerced_value)
        else
          invalid_attrs ||= {}
          invalid_attrs[attr.name] = coerced_value
        end
      end

      # TODO: aggregate all exceptions raised from #initialize into one big
      # exception that explains everything that went wrong, instead of multiple
      # smaller exceptions. Unfortunately, this would not be backwards
      # compatible.
      unless remaining_attrs.empty?
        raise UnrecognizedAttributes.new(
          "`#{self.class}` does not define attributes: " +
            remaining_attrs.map { |k| '`' + k.inspect + '`' }.join(', ')
        )
      end

      if missing_attrs
        raise MissingAttributes.new(
          "Some attributes required by `#{self.class}` are missing: " +
            missing_attrs.map { |a| "`#{a}`" }.join(', ')
        )
      end

      if invalid_attrs
        raise InvalidValue.new(
          "Some attributes of `#{self.class}` are invalid:\n" +
            invalid_attrs.map { |k,v| "  - #{k}: #{v.inspect}" }.join("\n") +
            "\n"
        )
      end
    end

    #
    # Returns the value for the given attribute name
    #
    # @param attr_name [Symbol] The name of the attribute. Can not be a +String+.
    # @return The value of the attribute
    #
    # @raise [UnrecognizedAttributes] if the attribute does not exist
    #
    def [](attr_name)
      attr = self.class.value_semantics.attributes.find do |attr|
        attr.name.equal?(attr_name)
      end

      if attr
        public_send(attr_name)
      else
        raise UnrecognizedAttributes, "`#{self.class}` has no attribute named `#{attr_name.inspect}`"
      end
    end

    #
    # Creates a copy of this object, with the given attributes changed (non-destructive update)
    #
    # @param new_attrs [Hash] the attributes to change
    # @return A new object, with the attribute changes applied
    #
    def with(new_attrs)
      self.class.new(internal_to_h.merge(new_attrs))
    end

    #
    # @return [Hash] all of the attributes
    #
    def to_h
      internal_to_h(sender: method(:public_send))
    end

    #
    # Loose equality
    #
    # @return [Boolean] whether all attributes are equal, and the object
    #                   classes are ancestors of eachother in any way
    #
    def ==(other)
      (other.is_a?(self.class) || is_a?(other.class)) && other.internal_to_h.eql?(to_h)
    end

    #
    # Strict equality
    #
    # @return [Boolean] whether all attribuets are equal, and both objects
    #                   has the exact same class
    #
    def eql?(other)
      other.class.equal?(self.class) && other.internal_to_h.eql?(internal_to_h)
    end

    #
    # Unique-ish integer, based on attributes and class of the object
    #
    def hash
      internal_to_h.hash ^ self.class.hash
    end

    def inspect
      attrs = internal_to_h
        .map { |key, value| "#{key}=#{value.inspect}" }
        .join(" ")

      "#<#{self.class} #{attrs}>"
    end

    def pretty_print(pp)
      pp.object_group(self) do
        internal_to_h.each do |attr, value|
          pp.breakable
          pp.text("#{attr}=")
          pp.pp(value)
        end
      end
    end

    def deconstruct_keys(_)
      to_h
    end

  protected

    def internal_to_h(sender: method(:send))
      self.class.value_semantics.attributes
        .map { |attr| [attr.name, sender.(attr.name)] }
        .to_h
    end

  end
end
