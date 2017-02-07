require 'cassandra'

CASSANDRA_HOSTS = ['cassandra']

module Utils
  def execute_statement(sess, desc, stmt)
    puts desc
    result = sess.execute(stmt)
  end

  def connect!
    cluster = Cassandra.cluster({ hosts: CASSANDRA_HOSTS, compression: :lz4 })
    cluster.connect('iotest')
  end
end
