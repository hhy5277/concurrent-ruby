require 'concurrent/edge/promises'
require 'thread'


RSpec.describe 'Concurrent::Promises' do

  include Concurrent::Promises::FactoryMethods

  describe 'chain_resolvable' do
    it 'event' do
      b = resolvable_event
      a = resolvable_event.chain_resolvable(b)
      a.resolve
      expect(b).to be_resolved
    end

    it 'future' do
      b = resolvable_future
      a = resolvable_future.chain_resolvable(b)
      a.fulfill :val
      expect(b).to be_resolved
      expect(b.value).to eq :val
    end
  end

  describe '.future' do
    it 'executes' do
      future = future { 1 + 1 }
      expect(future.value!).to eq 2

      future = fulfilled_future(1).then { |v| v + 1 }
      expect(future.value!).to eq 2
    end

    it 'executes with args' do
      future = future(1, 2, &:+)
      expect(future.value!).to eq 3

      future = fulfilled_future(1).then(1) { |v, a| v + 1 }
      expect(future.value!).to eq 2
    end
  end

  describe '.delay' do

    def behaves_as_delay(delay, value)
      expect(delay.resolved?).to eq false
      expect(delay.value!).to eq value
    end

    specify do
      behaves_as_delay delay { 1 + 1 }, 2
      behaves_as_delay fulfilled_future(1).delay.then { |v| v + 1 }, 2
      behaves_as_delay delay(1) { |a| a + 1 }, 2
      behaves_as_delay fulfilled_future(1).delay.then { |v| v + 1 }, 2
    end
  end

  describe '.schedule' do
    it 'scheduled execution' do
      start  = Time.now.to_f
      queue  = Queue.new
      future = schedule(0.1) { 1 + 1 }.then { |v| queue.push(v); queue.push(Time.now.to_f - start); queue }

      expect(future.value!).to eq queue
      expect(queue.pop).to eq 2
      expect(queue.pop).to be >= 0.09

      start  = Time.now.to_f
      queue  = Queue.new
      future = resolved_event.
          schedule(0.1).
          then { 1 }.
          then { |v| queue.push(v); queue.push(Time.now.to_f - start); queue }

      expect(future.value!).to eq queue
      expect(queue.pop).to eq 1
      expect(queue.pop).to be >= 0.09
    end

    it 'scheduled execution in graph' do
      start  = Time.now.to_f
      queue  = Queue.new
      future = future { sleep 0.1; 1 }.
          schedule(0.1).
          then { |v| v + 1 }.
          then { |v| queue.push(v); queue.push(Time.now.to_f - start); queue }

      future.wait!
      expect(future.value!).to eq queue
      expect(queue.pop).to eq 2
      expect(queue.pop).to be >= 0.09

      scheduled = resolved_event.schedule(0.1)
      expect(scheduled.resolved?).to be_falsey
      scheduled.wait
      expect(scheduled.resolved?).to be_truthy
    end

  end

  describe '.event' do
    specify do
      resolvable_event = resolvable_event()
      one              = resolvable_event.chain(1) { |arg| arg }
      join             = zip(resolvable_event).chain { 1 }
      expect(one.resolved?).to be false
      resolvable_event.resolve
      expect(one.value!).to eq 1
      expect(join.wait.resolved?).to be true
    end
  end

  describe '.future without block' do
    specify do
      resolvable_future = resolvable_future()
      one               = resolvable_future.then(&:succ)
      join              = zip_futures(resolvable_future).then { |v| v }
      expect(one.resolved?).to be false
      resolvable_future.fulfill 0
      expect(one.value!).to eq 1
      expect(join.wait!.resolved?).to be true
      expect(join.value!).to eq 0
    end
  end

  describe '.any_resolved' do
    it 'continues on first result' do
      f1 = resolvable_future
      f2 = resolvable_future
      f3 = resolvable_future

      any1 = any_resolved_future(f1, f2)
      any2 = f2 | f3

      f1.fulfill 1
      f2.reject StandardError.new

      expect(any1.value!).to eq 1
      expect(any2.reason).to be_a_kind_of StandardError
    end
  end

  describe '.any_fulfilled' do
    it 'continues on first result' do
      f1 = resolvable_future
      f2 = resolvable_future

      any = any_fulfilled_future(f1, f2)

      f1.reject StandardError.new
      f2.fulfill :value

      expect(any.value!).to eq :value
    end
  end

  describe '.zip' do
    it 'waits for all results' do
      a = future { 1 }
      b = future { 2 }
      c = future { 3 }

      z1 = a & b
      z2 = zip a, b, c
      z3 = zip a
      z4 = zip

      expect(z1.value!).to eq [1, 2]
      expect(z2.value!).to eq [1, 2, 3]
      expect(z3.value!).to eq [1]
      expect(z4.value!).to eq []

      q = Queue.new
      z1.then { |*args| q << args }
      expect(q.pop).to eq [1, 2]

      z1.then { |a1, b1, c1| q << [a1, b1, c1] }
      expect(q.pop).to eq [1, 2, nil]

      z2.then { |a1, b1, c1| q << [a1, b1, c1] }
      expect(q.pop).to eq [1, 2, 3]

      z3.then { |a1| q << a1 }
      expect(q.pop).to eq 1

      z3.then { |*as| q << as }
      expect(q.pop).to eq [1]

      z4.then { |a1| q << a1 }
      expect(q.pop).to eq nil

      z4.then { |*as| q << as }
      expect(q.pop).to eq []

      expect(z1.then { |a1, b1| a1 + b1 }.value!).to eq 3
      expect(z1.then { |a1, b1| a1 + b1 }.value!).to eq 3
      expect(z1.then(&:+).value!).to eq 3
      expect(z2.then { |a1, b1, c1| a1 + b1 + c1 }.value!).to eq 6

      expect(future { 1 }.delay).to be_a_kind_of Concurrent::Promises::Future
      expect(future { 1 }.delay.wait!).to be_resolved
      expect(resolvable_event.resolve.delay).to be_a_kind_of Concurrent::Promises::Event
      expect(resolvable_event.resolve.delay.wait).to be_resolved

      a = future { 1 }
      b = future { raise 'b' }
      c = future { raise 'c' }

      zip(a, b, c).chain { |*args| q << args }
      expect(q.pop.flatten.map(&:class)).to eq [FalseClass, 0.class, NilClass, NilClass, NilClass, RuntimeError, RuntimeError]
      zip(a, b, c).rescue { |*args| q << args }
      expect(q.pop.map(&:class)).to eq [NilClass, RuntimeError, RuntimeError]

      expect(zip.wait(0.1)).to eq true
    end

    context 'when a future raises an error' do

      let(:a_future) { future { raise 'error' } }

      it 'raises a concurrent error' do
        expect { zip(a_future).value! }.to raise_error(StandardError, 'error')
      end

      context 'when deeply nested' do
        it 'raises the original error' do
          expect { zip(zip(a_future)).value! }.to raise_error(StandardError, 'error')
        end
      end
    end
  end

  describe '.zip_events' do
    it 'waits for all and returns event' do
      a = fulfilled_future 1
      b = rejected_future :any
      c = resolvable_event.resolve

      z2 = zip_events a, b, c
      z3 = zip_events a
      z4 = zip_events

      expect(z2.resolved?).to be_truthy
      expect(z3.resolved?).to be_truthy
      expect(z4.resolved?).to be_truthy
    end
  end

  describe '.rejected_future' do
    it 'raises the correct error when passed an unraised error' do
      f = rejected_future(StandardError.new('boom'))
      expect { f.value! }.to raise_error(StandardError, 'boom')
    end
  end

  describe 'Future' do
    it 'has sync and async callbacks' do
      callbacks_tester = ->(event_or_future) do
        queue     = Queue.new
        push_args = -> *args { queue.push args }

        event_or_future.on_resolution!(&push_args)
        event_or_future.on_resolution!(1, &push_args)
        if event_or_future.is_a? Concurrent::Promises::Future
          event_or_future.on_fulfillment!(&push_args)
          event_or_future.on_fulfillment!(2, &push_args)
          event_or_future.on_rejection!(&push_args)
          event_or_future.on_rejection!(3, &push_args)
        end

        event_or_future.on_resolution(&push_args)
        event_or_future.on_resolution(4, &push_args)
        if event_or_future.is_a? Concurrent::Promises::Future
          event_or_future.on_fulfillment(&push_args)
          event_or_future.on_fulfillment(5, &push_args)
          event_or_future.on_rejection(&push_args)
          event_or_future.on_rejection(6, &push_args)
        end
        event_or_future.on_resolution_using(:io, &push_args)
        event_or_future.on_resolution_using(:io, 7, &push_args)
        if event_or_future.is_a? Concurrent::Promises::Future
          event_or_future.on_fulfillment_using(:io, &push_args)
          event_or_future.on_fulfillment_using(:io, 8, &push_args)
          event_or_future.on_rejection_using(:io, &push_args)
          event_or_future.on_rejection_using(:io, 9, &push_args)
        end

        event_or_future.wait
        ::Array.new(event_or_future.is_a?(Concurrent::Promises::Future) ? 12 : 6) { queue.pop }
      end

      callback_results = callbacks_tester.call(fulfilled_future(:v))
      expect(callback_results).to contain_exactly([true, :v, nil],
                                                  [true, :v, nil, 1],
                                                  [:v],
                                                  [:v, 2],
                                                  [true, :v, nil],
                                                  [true, :v, nil, 4],
                                                  [:v],
                                                  [:v, 5],
                                                  [true, :v, nil],
                                                  [true, :v, nil, 7],
                                                  [:v],
                                                  [:v, 8])

      err              = StandardError.new 'boo'
      callback_results = callbacks_tester.call(rejected_future(err))
      expect(callback_results).to contain_exactly([false, nil, err],
                                                  [false, nil, err, 1],
                                                  [err],
                                                  [err, 3],
                                                  [false, nil, err],
                                                  [false, nil, err, 4],
                                                  [err],
                                                  [err, 6],
                                                  [false, nil, err],
                                                  [false, nil, err, 7],
                                                  [err],
                                                  [err, 9])

      callback_results = callbacks_tester.call(resolved_event)
      expect(callback_results).to contain_exactly([], [1], [], [4], [], [7])
    end

    methods_with_timeout = { wait:   false,
                             wait!:  false,
                             value:  nil,
                             value!: nil,
                             reason: nil,
                             result: nil }
    methods_with_timeout.each do |method_with_timeout, timeout_value|
      it "#{ method_with_timeout } supports setting timeout" do
        start_latch = Concurrent::CountDownLatch.new
        end_latch   = Concurrent::CountDownLatch.new

        future = future do
          start_latch.count_down
          end_latch.wait(0.2)
        end

        expect(start_latch.wait(0.1)).to eq true
        expect(future).not_to be_resolved
        expect(future.send(method_with_timeout, 0.01)).to eq timeout_value
        expect(future).not_to be_resolved

        end_latch.count_down
        expect(future.value!).to eq true
      end
    end

    it 'chains' do
      future0 = future { 1 }.then { |v| v + 2 } # both executed on default FAST_EXECUTOR
      future1 = future0.then_on(:fast) { raise 'boo' } # executed on IO_EXECUTOR
      future2 = future1.then { |v| v + 1 } # will reject with 'boo' error, executed on default FAST_EXECUTOR
      future3 = future1.rescue { |err| err.message } # executed on default FAST_EXECUTOR
      future4 = future0.chain { |success, value, reason| success } # executed on default FAST_EXECUTOR
      future5 = future3.with_default_executor(:fast) # connects new future with different executor, the new future is resolved when future3 is
      future6 = future5.then(&:capitalize) # executes on IO_EXECUTOR because default was set to :io on future5
      future7 = future0 & future3
      future8 = future0.rescue { raise 'never happens' } # future0 fulfills so future8'll have same value as future 0

      futures = [future0, future1, future2, future3, future4, future5, future6, future7, future8]
      futures.each(&:wait)

      table = futures.each_with_index.map do |f, i|
        '%5i %7s %10s %6s %4s %6s' % [i, f.fulfilled?, f.value, f.reason,
                                      (f.promise.executor if f.promise.respond_to?(:executor)),
                                      f.default_executor]
      end.unshift('index success      value reason pool d.pool')

      expect(table.join("\n")).to eq <<-TABLE.gsub(/^\s+\|/, '').strip
        |index success      value reason pool d.pool
        |    0    true          3          io     io
        |    1   false               boo fast     io
        |    2   false               boo   io     io
        |    3    true        boo          io     io
        |    4    true       true          io     io
        |    5    true        boo               fast
        |    6    true        Boo        fast   fast
        |    7    true [3, "boo"]                 io
        |    8    true          3          io     io
      TABLE
    end

    it 'constructs promise like tree' do
      # if head of the tree is not constructed with #future but with #delay it does not start execute,
      # it's triggered later by calling wait or value on any of the dependent futures or the delay itself
      three = (head = delay { 1 }).then { |v| v.succ }.then(&:succ)
      four  = three.delay.then(&:succ)

      # meaningful to_s and inspect defined for Future and Promise
      expect(head.to_s).to match(/#<Concurrent::Promises::Future:0x[\da-f]+ pending>/)
      expect(head.inspect).to(
          match(/#<Concurrent::Promises::Future:0x[\da-f]+ pending>/))

      # evaluates only up to three, four is left unevaluated
      expect(three.value!).to eq 3
      expect(four).not_to be_resolved

      expect(four.value!).to eq 4

      # futures hidden behind two delays trigger evaluation of both
      double_delay = delay { 1 }.delay.then(&:succ)
      expect(double_delay.value!).to eq 2
    end

    it 'allows graphs' do
      head    = future { 1 }
      branch1 = head.then(&:succ)
      branch2 = head.then(&:succ).delay.then(&:succ)
      results = [
          zip(branch1, branch2).then { |b1, b2| b1 + b2 },
          branch1.zip(branch2).then { |b1, b2| b1 + b2 },
          (branch1 & branch2).then { |b1, b2| b1 + b2 }]

      Thread.pass until branch1.resolved?
      expect(branch1).to be_resolved
      expect(branch2).not_to be_resolved

      expect(results.map(&:value)).to eq [5, 5, 5]
      expect(zip(branch1, branch2).value!).to eq [2, 3]
    end

    describe '#flat' do
      it 'returns value of inner future' do
        f = future { future { 1 } }.flat.then(&:succ)
        expect(f.value!).to eq 2
      end

      it 'propagates rejection of inner future' do
        err = StandardError.new('boo')
        f   = future { rejected_future(err) }.flat
        expect(f.reason).to eq err
      end

      it 'it propagates rejection of the future which was suppose to provide inner future' do
        f = future { raise 'boo' }.flat
        expect(f.reason.message).to eq 'boo'
      end

      it 'rejects if inner value is not a future' do
        f = future { 'boo' }.flat
        expect(f.reason).to be_an_instance_of TypeError

        f = future { resolved_event }.flat
        expect(f.reason).to be_an_instance_of TypeError
      end

      it 'propagates requests for values to delayed futures' do
        expect(future { delay { 1 } }.flat.value!(0.1)).to eq 1
        expect(::Array.new(3) { |i| Concurrent::Promises.delay { i } }.
            inject { |a, b| a.then { b }.flat }.value!(0.2)).to eq 2
      end

      it 'has shortcuts' do
        expect(fulfilled_future(1).then_flat { |v| future(v) { v + 1 } }.value!).to eq 2
        expect(fulfilled_future(1).then_flat_event { |v| resolved_event }.wait.resolved?).to eq true
        expect(fulfilled_future(1).then_flat_on(:fast) { |v| future(v) { v + 1 } }.value!).to eq 2
      end
    end

    it 'resolves future when Exception raised' do
      message = 'reject by an Exception'
      future  = future { raise Exception, message }
      expect(future.wait(0.1)).to eq true
      future.wait
      expect(future).to be_resolved
      expect(future).to be_rejected

      expect(future.reason).to be_instance_of Exception
      expect(future.result).to be_instance_of Array
      expect(future.value).to be_nil
      expect { future.value! }.to raise_error(Exception, message)
    end

    it 'runs' do
      body = lambda do |v|
        v += 1
        v < 5 ? future(v, &body) : v
      end
      expect(future(0, &body).run.value!).to eq 5

      body = lambda do |v|
        v += 1
        v < 5 ? future(v, &body) : raise(v.to_s)
      end
      expect(future(0, &body).run.reason.message).to eq '5'
    end

    it 'can be risen when rejected' do
      strip_methods = -> backtrace do
        backtrace.map do |line|
          /^.*:\d+:in/.match(line)[0] rescue line
        end
      end

      future    = rejected_future TypeError.new
      backtrace = caller; exception = (raise future rescue $!)
      expect(exception).to be_a TypeError
      expect(strip_methods[backtrace] - strip_methods[exception.backtrace]).to be_empty

      exception = TypeError.new
      exception.set_backtrace(first_backtrace = %W[/a /b /c])
      future    = rejected_future exception
      backtrace = caller; exception = (raise future rescue $!)
      expect(exception).to be_a TypeError
      expect(strip_methods[first_backtrace + backtrace] - strip_methods[exception.backtrace]).to be_empty

      future    = rejected_future(TypeError.new) & rejected_future(TypeError.new)
      backtrace = caller; exception = (raise future rescue $!)
      expect(exception).to be_a Concurrent::MultipleErrors
      expect(strip_methods[backtrace] - strip_methods[exception.backtrace]).to be_empty
    end
  end

  describe 'interoperability' do
    it 'with actor', if: !defined?(JRUBY_VERSION) do
      actor = Concurrent::Actor::Utils::AdHoc.spawn :doubler do
        -> v { v * 2 }
      end

      expect(future { 2 }.
          then_ask(actor).
          then { |v| v + 2 }.
          value!).to eq 6
    end

    it 'with channel' do
      ch1 = Concurrent::Promises::Channel.new
      ch2 = Concurrent::Promises::Channel.new

      result = Concurrent::Promises.select_channel(ch1, ch2)
      ch1.push 1
      expect(result.value!).to eq [ch1, 1]


      future { 1+1 }.then_push_channel(ch1)
      result = (Concurrent::Promises.future { '%02d' } & Concurrent::Promises.select_channel(ch1, ch2)).
          then { |format, (channel, value)| format format, value }
      expect(result.value!).to eq '02'
    end
  end

  describe 'Cancellation', edge: true do
    specify do
      source, token = Concurrent::Cancellation.create

      futures = ::Array.new(2) { future(token) { |t| t.loop_until_canceled { Thread.pass }; :done } }

      source.cancel
      futures.each do |future|
        expect(future.value!).to eq :done
      end
    end

    specify do
      source, token = Concurrent::Cancellation.create
      source.cancel
      expect(token.canceled?).to be_truthy

      cancellable_branch = Concurrent::Promises.delay { 1 }
      expect((cancellable_branch | token.to_event).value).to be_nil
      expect(cancellable_branch.resolved?).to be_falsey
    end

    specify do
      source, token = Concurrent::Cancellation.create

      cancellable_branch = Concurrent::Promises.delay { 1 }
      expect(any_resolved_future(cancellable_branch, token.to_event).value).to eq 1
      expect(cancellable_branch.resolved?).to be_truthy
    end

    specify do
      source, token = Concurrent::Cancellation.create(
          Concurrent::Promises.resolvable_future, false, nil, err = StandardError.new('Cancelled'))
      source.cancel
      expect(token.canceled?).to be_truthy

      cancellable_branch = Concurrent::Promises.delay { 1 }
      expect((cancellable_branch | token.to_future).reason).to eq err
      expect(cancellable_branch.resolved?).to be_falsey
    end
  end

  describe 'Promises::Channel' do
    specify do
      channel = Concurrent::Promises::Channel.new 1

      pushed1 = channel.push 1
      expect(pushed1.resolved?).to be_truthy
      expect(pushed1.value!).to eq 1

      pushed2 = channel.push 2
      expect(pushed2.resolved?).to be_falsey

      popped = channel.pop
      expect(pushed1.value!).to eq 1
      expect(pushed2.resolved?).to be_truthy
      expect(pushed2.value!).to eq 2
      expect(popped.value!).to eq 1

      popped = channel.pop
      expect(popped.value!).to eq 2

      popped = channel.pop
      expect(popped.resolved?).to be_falsey

      pushed3 = channel.push 3
      expect(popped.value!).to eq 3
      expect(pushed3.resolved?).to be_truthy
      expect(pushed3.value!).to eq 3
    end

    specify do
      ch1 = Concurrent::Promises::Channel.new
      ch2 = Concurrent::Promises::Channel.new
      ch3 = Concurrent::Promises::Channel.new

      add = -> do
        (ch1.pop & ch2.pop).then do |a, b|
          if a == :done && b == :done
            :done
          else
            ch3.push a + b
            add.call
          end
        end
      end

      ch1.push 1
      ch2.push 2
      ch1.push 'a'
      ch2.push 'b'
      ch1.push nil
      ch2.push true

      result = Concurrent::Promises.future(&add).run.result
      expect(result[0..1]).to eq [false, nil]
      expect(result[2]).to be_a_kind_of(NoMethodError)
      expect(ch3.pop.value!).to eq 3
      expect(ch3.pop.value!).to eq 'ab'

      ch1.push 1
      ch2.push 2
      ch1.push 'a'
      ch2.push 'b'
      ch1.push :done
      ch2.push :done

      expect(Concurrent::Promises.future(&add).run.result).to eq [true, :done, nil]
      expect(ch3.pop.value!).to eq 3
      expect(ch3.pop.value!).to eq 'ab'
    end
  end
end

RSpec.describe Concurrent::ProcessingActor do
  specify do
    actor = Concurrent::ProcessingActor.act do |the_actor|
      the_actor.receive.then do |message|
        # the actor ends with message
        message
      end
    end #

    actor.tell! :a_message
    expect(actor.termination.value!).to eq :a_message

    def count(actor, count)
      # the block passed to receive is called when the actor receives the message
      actor.receive.then do |number_or_command, answer|
        # code which is evaluated after the number is received
        case number_or_command
        when :done
          # this will become the result (final value) of the actor
          count
        when :count
          # reply the current count
          answer.fulfill count
          # continue running
          count(actor, count)
        when Integer
          # this will call count again to set up what to do on next message, based on new state `count + numer`
          count(actor, count + number_or_command)
        end
      end
      # evaluation of count ends immediately
      # code which is evaluated before the number is received, should be empty
    end

    counter = Concurrent::ProcessingActor.act { |a| count a, 0 }
    expect(counter.tell!(2).ask(:count).value!).to eq 2
    expect(counter.tell!(3).tell!(:done).termination.value!).to eq 5

    add_once_actor = Concurrent::ProcessingActor.act do |the_actor|
      the_actor.receive.then do |(a, b), answer|
        result = a + b
        answer.fulfill result
        # terminate with result value
        result
      end
    end

    expect(add_once_actor.ask([1, 2]).value!).to eq 3
    expect(add_once_actor.ask(%w(ab cd)).reason).to be_a_kind_of RuntimeError
    expect(add_once_actor.termination.value!).to eq 3

    def pair_adder(actor)
      (actor.receive & actor.receive).then do |(value1, answer1), (value2, answer2)|
        result = value1 + value2
        answer1.fulfill result if answer1
        answer2.fulfill result if answer2
        pair_adder actor
      end
    end

    pair_adder = Concurrent::ProcessingActor.act { |a| pair_adder a }

    expect(pair_adder.tell!(3).ask(2).value!).to eq 5
    expect((pair_adder.ask('a') & pair_adder.ask('b')).value!).to eq %w[ab ab]
    expect((pair_adder.ask('a') | pair_adder.ask('b')).value!).to eq 'ab'
  end
end
