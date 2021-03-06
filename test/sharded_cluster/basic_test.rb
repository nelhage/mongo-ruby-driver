require 'test_helper'

class BasicTest < Test::Unit::TestCase
  def setup
    ensure_cluster(:sc)
  end

  def self.shutdown
    @@cluster.stop
    @@cluster.clobber
  end

  # TODO member.primary? ==> true
  def test_connect
    seeds = @sc.mongos_seeds
    @client = Mongo::ShardedClient.new(seeds)
    assert @client.connected?
    assert_equal(seeds.size, @client.seeds.size)
    probe(seeds.size)
    @client.close
  end

  def test_hard_refresh
    seeds = @sc.mongos_seeds
    @client = Mongo::ShardedClient.new(seeds)
    assert @client.connected?
    @client.hard_refresh!
    assert @client.connected?
    @client.close
  end

  def test_reconnect
    seeds = @sc.mongos_seeds
    @client = Mongo::ShardedClient.new(seeds)
    assert @client.connected?
    router = @sc.servers(:routers).first
    router.stop
    probe(seeds.size)
    assert @client.connected?
    @client.close
  end

  def test_all_down
    seeds = @sc.mongos_seeds
    @client = Mongo::ShardedClient.new(seeds)
    assert @client.connected?
    @sc.servers(:routers).each{|router| router.stop}
    assert_raises Mongo::ConnectionFailure do
      probe(seeds.size)
    end
    assert_false @client.connected?
    @client.close
  end

  def test_cycle
    seeds = @sc.mongos_seeds
    @client = Mongo::ShardedClient.new(seeds)
    assert @client.connected?
    routers = @sc.servers(:routers)
    while routers.size > 0 do
      rescue_connection_failure do
        probe(seeds.size)
      end
      probe(seeds.size)
      router = routers.detect{|r| r.port == @client.manager.primary.last}
      routers.delete(router)
      router.stop
    end
    assert_raises Mongo::ConnectionFailure do
      probe(seeds.size)
    end
    assert_false @client.connected?
    routers = @sc.servers(:routers).reverse
    routers.each do |r|
      r.start
      @client.hard_refresh!
      rescue_connection_failure do
        probe(seeds.size)
      end
      probe(seeds.size)
    end
    @client.close
  end

  private

  def probe(size)
    assert_equal(size, @client['config']['mongos'].find.to_a.size)
  end

end
