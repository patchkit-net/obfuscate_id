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
end
