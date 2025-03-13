require 'spec_helper'

describe ObfuscateId do
  describe '#obfuscate_id_spin' do
    let(:user) { User.new(id: 1) }
    let(:post) { Post.new(id: 1) }

    context 'when spin defined' do
      before do
        class User < ActiveRecord::Base
          obfuscate_id spin: 987_654_321
        end

        class Post < ActiveRecord::Base
          obfuscate_id spin: 123_456_789
        end
      end

      it 'reports correct value' do
        expect(User.obfuscate_id_spin).to eql 987_654_321
        expect(Post.obfuscate_id_spin).to eql 123_456_789
      end

      it 'uses the spin given' do
        expect(user.to_param).to_not eql post.to_param
      end
    end

    context 'when not defined' do
      before do
        class User < ActiveRecord::Base
          obfuscate_id
        end

        class Post < ActiveRecord::Base
          obfuscate_id
        end
      end

      it 'reports a unique value computed from model name' do
        expect(User.obfuscate_id_spin).to_not eql Post.obfuscate_id_spin
      end

      it 'uses computed spin' do
        expect(user.to_param).to_not eql post.to_param
      end

      describe 'for model with long name' do
        before do
          class SomeReallyAbsurdlyLongNamedClassThatYouWouldntHaveThoughtOfs < ActiveRecord::Base
            def self.columns
              @columns ||= []
            end

            def self.column(name, sql_type = nil, default = nil, null = true)
              columns << ActiveRecord::ConnectionAdapters::Column.new(name.to_s, default, sql_type.to_s, null)
            end

            obfuscate_id
          end
        end

        it 'compute default spin correctly' do
          rec = SomeReallyAbsurdlyLongNamedClassThatYouWouldntHaveThoughtOfs.new(id: 1)
          expect { rec.to_param }.not_to raise_error
        end
      end
    end
  end

  describe '#deobfuscate_id' do
    before do
      class User < ActiveRecord::Base
        obfuscate_id
      end
    end

    let(:user) { User.create(id: 1) }

    subject(:deobfuscated_id) { User.deobfuscate_id(user.to_param).to_i }

    it 'reverses the obfuscated id' do
      should eq(user.id)
    end
  end

  describe 'with symbol as name option' do
    it 'handles symbol name without errors' do
      result = ObfuscateId.hide(123, :int, 1_234_567)
      expect(result).to start_with('int-')
      expect(ObfuscateId.show(result, :int, 1_234_567).to_i).to eq(123)
    end

    it 'works with the specific :int symbol reported in the issue' do
      test_id = 3
      # Test direct method calls instead of using a model
      obfuscated = ObfuscateId.hide(test_id, :int, 20_151_514_171_913_142_211)
      expect(obfuscated).to start_with('int-')
      expect(ObfuscateId.show(obfuscated, :int, 20_151_514_171_913_142_211).to_i).to eq(test_id)

      # The truncate_spin method should properly handle the large spin
      spin = 20_151_514_171_913_142_211
      truncated_spin = ObfuscateId.send(:truncate_spin, spin)
      expect(truncated_spin).to be <= 999_999_999
      expect(ScatterSwap::Hasher.new(test_id, truncated_spin)).to be_a(ScatterSwap::Hasher)
    end
  end

  describe 'enforce_obfuscated option' do
    let(:user) { User.create(id: 1) }
    let(:obfuscated_id) { user.to_param }
    let(:raw_id) { user.id.to_s }

    context 'when enforce_obfuscated is true and raise_errors is false' do
      before do
        class User < ActiveRecord::Base
          obfuscate_id name: 'user', enforce_obfuscated: true
        end
      end

      it 'raises ActiveRecord::RecordNotFound when trying to find by raw id' do
        expect { User.find(raw_id) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'finds the record when using obfuscated id' do
        expect(User.find(obfuscated_id)).to eq(user)
      end

      it 'raises ActiveRecord::RecordNotFound when trying to find multiple with raw ids' do
        expect { User.find([raw_id]) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'finds multiple records when using obfuscated ids' do
        expect(User.find([obfuscated_id])).to eq([user])
      end
    end

    context 'when enforce_obfuscated and raise_errors are true' do
      before do
        class User < ActiveRecord::Base
          obfuscate_id name: 'user', enforce_obfuscated: true, raise_errors: true
        end
      end

      it 'raises NonObfuscatedIdError when trying to find by raw id' do
        expect { User.find(raw_id) }.to raise_error(ObfuscateId::NonObfuscatedIdError)
      end

      it 'includes helpful message in the error' do
        User.find(raw_id)
      rescue ObfuscateId::NonObfuscatedIdError => e
        expect(e.message).to include("requires obfuscated IDs with prefix 'user-'")
      end

      it 'finds the record when using obfuscated id' do
        expect(User.find(obfuscated_id)).to eq(user)
      end

      it 'raises NonObfuscatedIdError when trying to find multiple with raw ids' do
        expect { User.find([raw_id]) }.to raise_error(ObfuscateId::NonObfuscatedIdError)
      end

      it 'finds multiple records when using obfuscated ids' do
        expect(User.find([obfuscated_id])).to eq([user])
      end
    end

    context 'when name is not provided with enforce_obfuscated' do
      it 'raises an ArgumentError' do
        expect do
          class InvalidUser < ActiveRecord::Base
            obfuscate_id enforce_obfuscated: true
          end
        end.to raise_error(ArgumentError, "Option 'name' must be set when 'enforce_obfuscated' is true")
      end
    end
  end

  context 'with direct call to scatter_swap' do
    it 'handles symbols in the ScatterSwap calls' do
      require 'scatter_swap'

      # Testing if a direct call to ScatterSwap with a Symbol would cause the RangeError
      id = 9_223_372_036_854_775_807 # Max 64-bit integer
      name = :int

      # If this fails with a RangeError, it would confirm the issue
      expect do
        ObfuscateId.hide(id, name, 1234)
      end.not_to raise_error

      # Try an even larger number
      huge_id = 18_446_744_073_709_551_615 # 2^64 - 1

      # In this environment, ScatterSwap can handle large numbers without issues
      expect do
        # Test ScatterSwap directly
        ScatterSwap.hash(huge_id, 1234)
      end.not_to raise_error
    end
  end

  describe 'with very large spin value' do
    it 'handles the large spin without error' do
      # This is the specific value that caused the error in production
      large_spin = 20_151_514_171_913_142_211

      # These are the exact arguments from the stack trace
      # Using Kernel.eval to bypass the Ruby parser's limit on integer size
      expect do
        # We need a direct call to the ScatterSwap::Hasher's internal method
        # since that's where the error occurs
        plain_integer = 3
        spin = large_spin
        hasher = ScatterSwap::Hasher.new(plain_integer, spin)

        # Force the error to occur by calling the method that performs the rotate
        hasher.send(:swapper_map, 0)
      end.to raise_error(RangeError, /bignum too big to convert into `long'/)
    end
  end

  describe '#truncate_spin' do
    before do
      class User < ActiveRecord::Base
        obfuscate_id
      end
    end

    it 'truncates large spin values to a safe size' do
      large_spin = 20_151_514_171_913_142_211
      truncated_spin = User.truncate_spin(large_spin)

      # Ensure it's less than our maximum safe value
      expect(truncated_spin).to be <= 999_999_999

      # Ensure we can use it without errors
      expect do
        hasher = ScatterSwap::Hasher.new(3, truncated_spin)
        hasher.send(:swapper_map, 0)
      end.not_to raise_error
    end

    it 'leaves small spin values unchanged' do
      small_spin = 123_456_789
      expect(User.truncate_spin(small_spin)).to eq small_spin
    end
  end
end
