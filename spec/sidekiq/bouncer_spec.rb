module Rails; end

class FooWorker
  def self.bouncer
    @bouncer ||= Sidekiq::Bouncer.new(self)
  end
end

RSpec.describe Sidekiq::Bouncer do
  let(:klass) { FooWorker }
  let(:param1) { 1 }
  let(:param2) { 2 }
  let(:key) { "#{klass}:#{param1},#{param2}" }
  let(:now) { 100 }

  subject { FooWorker.bouncer }

  describe '#debounce' do
    before do
      allow(subject).to receive(:now).and_return(now)
      allow(Rails).to receive_message_chain(:application, :redis, :set)
      allow(klass).to receive(:perform_at)
    end

    it 'sets Redis with delayed timestamp' do
      subject.debounce(param1, param2)

      expect(Rails.application.redis)
        .to have_received(:set)
        .with(key, now + described_class::DEFAULT_DELAY)
    end

    it 'queues Sidekiq with delayed and buffered timestamp' do
      subject.debounce(param1, param2)

      expect(klass)
        .to have_received(:perform_at)
        .with(
          now + described_class::DEFAULT_DELAY + described_class::BUFFER,
          param1,
          param2
        )
    end
  end

  describe '#let_in?' do
    context 'when debounce timestamp is in the past' do
      before do
        allow(Rails)
          .to receive_message_chain(:application, :redis, :get)
          .and_return(Time.now - 10)
        allow(Rails).to receive_message_chain(:application, :redis, :del)
      end

      it 'returns true' do
        expect(subject.let_in?(param1, param2)).to eq(true)
      end

      it 'deletes debounce timestamp from redis' do
        subject.let_in?(param1, param2)
        expect(Rails.application.redis).to have_received(:del).with(key)
      end
    end

    context 'when debounce timestamp is in the future' do
      before do
        allow(Rails)
          .to receive_message_chain(:application, :redis, :get)
          .and_return(Time.now + 10)
      end

      it 'returns false' do
        expect(subject.let_in?(param1, param2)).to eq(false)
      end
    end

    context 'when debounce timestamp is not there' do
      before do
        allow(Rails)
          .to receive_message_chain(:application, :redis, :get)
          .and_return(nil)
      end

      it 'returns false' do
        expect(subject.let_in?(param1, param2)).to eq(false)
      end
    end
  end
end
