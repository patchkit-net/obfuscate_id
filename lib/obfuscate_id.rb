module ObfuscateId
  extend ActiveSupport::Concern

  # Custom exception for non-obfuscated IDs when enforce_obfuscated is true
  class NonObfuscatedIdError < StandardError; end

  def obfuscate_id(options = {})
    require 'scatter_swap'

    if options[:enforce_obfuscated] && options[:name].nil?
      raise ArgumentError, "Option 'name' must be set when 'enforce_obfuscated' is true"
    end

    extend ClassMethods
    include InstanceMethods

    cattr_accessor :obfuscate_id_spin, :clean_url_class_name, :enforce_obfuscated, :raise_errors

    self.obfuscate_id_spin = (options[:spin] || obfuscate_id_default_spin)
    self.enforce_obfuscated = options[:enforce_obfuscated] || false
    self.raise_errors = options[:raise_errors] || false
    set_clean_url_class_name(name: options[:name])
  end

  # Truncate a spin value to a safe size (max 9 digits)
  # to prevent RangeError in ScatterSwap's rotate! method
  def self.truncate_spin(spin)
    max_safe_spin = 999_999_999 # 9 digits
    spin_int = spin.to_i
    if spin_int > max_safe_spin
      spin_int % max_safe_spin
    else
      spin_int
    end
  end

  def self.hide(id, name, spin)
    id = id.to_i
    name = name.to_s
    # Use truncate_spin for spin value to prevent RangeError
    safe_spin = truncate_spin(spin)
    "#{name}-" + ScatterSwap.hash(id, safe_spin)
  end

  def self.show(id, name, spin)
    name = name.to_s
    # Strip off the name prefix
    id = id[name.length + 1..-1] if id.to_s.starts_with?("#{name}-")
    # Use truncate_spin for spin value to prevent RangeError
    safe_spin = truncate_spin(spin)
    ScatterSwap.reverse_hash(id, safe_spin)
  end

  module ClassMethods
    def set_clean_url_class_name(name: nil)
      self.clean_url_class_name = name || self.name.gsub('::', '-').underscore
    end

    def find(*args)
      scope = args.slice!(0)

      if scope.is_a?(Array)
        if enforce_obfuscated
          valid_ids = []
          scope.each do |a|
            if !a.to_s.start_with?("#{clean_url_class_name}-")
              raise ActiveRecord::RecordNotFound, "Couldn't find #{name} with non-obfuscated ID" unless raise_errors

              raise NonObfuscatedIdError,
                    "#{name} requires obfuscated IDs with prefix '#{clean_url_class_name}-'"

            # Use RecordNotFound to match ActiveRecord behavior

            else
              valid_ids << deobfuscate_id(a).to_i
            end
          end
          scope = valid_ids
        else
          scope.map! { |a| deobfuscate_id(a).to_i }
        end
      elsif enforce_obfuscated && !scope.to_s.start_with?("#{clean_url_class_name}-")
        raise ActiveRecord::RecordNotFound, "Couldn't find #{name} with non-obfuscated ID" unless raise_errors

        raise NonObfuscatedIdError,
              "#{name} requires obfuscated IDs with prefix '#{clean_url_class_name}-'"

        # Use RecordNotFound to match ActiveRecord behavior

      else
        scope = deobfuscate_id(scope)
      end

      super(scope)
    end

    def deobfuscate_id(obfuscated_id)
      # Ensure clean_url_class_name is a string
      class_name_str = clean_url_class_name.to_s
      if obfuscated_id.to_s.start_with? "#{class_name_str}-"
        ObfuscateId.show(obfuscated_id, class_name_str, obfuscate_id_spin)
      else
        obfuscated_id
      end
    end

    # Truncate a spin value to a safe size (max 9 digits)
    # to prevent RangeError in ScatterSwap's rotate! method
    def truncate_spin(spin)
      ObfuscateId.truncate_spin(spin)
    end

    # Generate a default spin from the model name
    # This makes it different for each model
    def obfuscate_id_default_spin
      alphabet = Array('a'..'z')
      number = name.split('').collect do |char|
        alphabet.index(char)
      end

      truncate_spin(number.shift(12).join.to_i)
    end
  end

  module InstanceMethods
    def to_param
      ObfuscateId.hide(id, clean_url_class_name, self.class.obfuscate_id_spin)
    end

    def deobfuscate_id(obfuscated_id)
      self.class.deobfuscate_id(obfuscated_id)
    end
  end
end

ActiveRecord::Base.extend ObfuscateId
