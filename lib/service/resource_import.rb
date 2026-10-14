# frozen_string_literal: true

module Service
  class ResourceImport
    def initialize(resource, only: nil, except: nil)
      raise ArgumentError, "only and except cannot be used together." if only && except
      if !resource && (only || except)
        raise ArgumentError, "#{only ? :only : :except} requires from_resource."
      end

      @attributes = resource ? resource.writable_attributes.index_by(&:name) : {}
      @only = only.try { it.map(&:to_s) }
      @except = (except || []).map(&:to_s)
      verify!
    end

    def apply_to(contract)
      selected_attributes.each_value { contract.attribute(it.name, it.type) }
    end

    private

    attr_reader :attributes, :only, :except

    def selected_attributes
      return attributes.slice(*only) if only
      attributes.except(*except)
    end

    def verify!
      unknown_names = (only || except) - attributes.keys
      return if unknown_names.empty?
      raise ArgumentError, "#{unknown_names.join(", ")} are not writable resource attributes."
    end
  end
end
