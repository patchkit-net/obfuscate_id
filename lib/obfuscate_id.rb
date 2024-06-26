module ObfuscateId
  def obfuscate_id(options = {})
    require 'scatter_swap'

    extend ClassMethods
    include InstanceMethods

    cattr_accessor :obfuscate_id_spin, :clean_url_class_name

    self.obfuscate_id_spin = (options[:spin] || obfuscate_id_default_spin)
    set_clean_url_class_name(name: options[:name])
  end

  def self.hide(id, name, spin)
    "#{name}-" + ScatterSwap.hash(id, spin)
  end

  def self.show(id, name, spin)
    ScatterSwap.reverse_hash(id.gsub("#{name}-", ''), spin)
  end

  module ClassMethods

    def set_clean_url_class_name(name: nil)
      self.clean_url_class_name = name || self.name.gsub("::", "-").underscore
    end

    def find(*args)
      scope = args.slice!(0)

      if scope.is_a?(Array)
        scope.map! {|a| deobfuscate_id(a).to_i}
      else
        scope = deobfuscate_id(scope)
      end

      super(scope)
    end

    def deobfuscate_id(obfuscated_id)
      if obfuscated_id.to_s.start_with? "#{self.clean_url_class_name}-"
        ObfuscateId.show(obfuscated_id, self.clean_url_class_name, self.obfuscate_id_spin)
      else
        obfuscated_id
      end
    end

    # Generate a default spin from the Model name
    # This makes it easy to drop obfuscate_id onto any model
    # and produce different obfuscated ids for different models
    def obfuscate_id_default_spin
      alphabet = Array("a".."z")
      number = name.split("").collect do |char|
        alphabet.index(char)
      end

      number.shift(12).join.to_i
    end
  end

  module InstanceMethods
    def to_param
      ObfuscateId.hide(self.id, self.clean_url_class_name, self.class.obfuscate_id_spin)
    end

    def deobfuscate_id(obfuscated_id)
      self.class.deobfuscate_id(obfuscated_id)
    end
  end
end

ActiveRecord::Base.extend ObfuscateId
