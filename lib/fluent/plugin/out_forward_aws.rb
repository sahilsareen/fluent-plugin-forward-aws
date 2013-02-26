class Fluent::ForwardAWSOutput < Fluent::TimeSlicedOutput
  Fluent::Plugin.register_output('forward-aws', self)

  # config_param :hoge, :string, :default => 'hoge'

  config_param :channel, :string, :default => "default"

  config_param :aws_access_key_id, :string, :default => nil
  config_param :aws_secret_access_key, :string, :default => nil
  
  config_param :aws_s3_endpoint, :string, :default => nil
  config_param :aws_s3_bucketname, :string, :default => nil
  config_param :aws_s3_testobjectname, :string, :default => "Config Check Test Object"
  config_param :aws_s3_skiptest, :bool, :default => false
  
  config_param :aws_sns_endpoint, :string, :default => nil
  config_param :aws_sns_topic_arn, :string, :default => nil
  config_param :aws_sns_skiptest, :bool, :default => false

  def initialize
    super
    require 'aws-sdk'
    require 'zlib'
    require 'tempfile'
    require 'json'
    require 'securerandom'
  end

  def configure(conf)
    super
    @path = conf['path']
    unless @aws_access_key_id
      raise Fluent::ConfigError.new("aws_access_key_id is required")
    end
    unless @aws_secret_access_key
      raise Fluent::ConfigError.new("aws_secret_access_key is required")
    end
    unless @aws_s3_endpoint
      raise Fluent::ConfigError.new("aws_s3_endpoint is required")
    end
    unless @aws_s3_bucketname
      raise Fluent::ConfigError.new("aws_s3_bucketname is required")
    end
    unless @aws_sns_endpoint
      raise Fluent::ConfigError.new("aws_sns_endpoint is required")
    end
    unless @aws_sns_topic_arn
      raise Fluent::ConfigError.new("aws_sns_topic_arn is required")
    end
    unless(@aws_s3_skiptest)
      init_aws_s3_bucket()
      begin
        @bucket.objects[@aws_s3_testobjectname].write("TEST", :content_type => 'text/plain')
      rescue
        raise Fluent::ConfigError.new("Cannot put object to S3. Need s3:PutObject permission for resource arn:aws:s3:::" + @aws_s3_bucketname+"/*")
      end
    end
    unless(@aws_sns_skiptest)
      init_aws_sns_topic()
      begin
        @topic.publish('', :subject => "SNS Message", :email =>JSON.pretty_generate({"type" => "ping"}))
      rescue
        raise Fluent::ConfigError.new("Cannot post notification to SNS. Need sns:Publish permission for resource " + @aws_sns_topic_arn)
      end
    end
  end

  def start
    super
    init_aws_s3_bucket()
    init_aws_sns_topic()
  end

  def shutdown
    super
    # destroy
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def write(chunk)
    #Add UUID to avoid name conflict
    s3path = "#{@channel}/#{chunk.key}/#{SecureRandom.uuid}.gz"
    
    # Create temp gzip file
    tmpFile = Tempfile.new("forward-aws-")
    writer = Zlib::GzipWriter.new(tmpFile)
    begin
      chunk.write_to(writer)
      writer.close
      @bucket.objects[s3path].write(Pathname.new(tmpFile.path), :content_type => 'application/x-gzip')
      @topic.publish('', :subject => "SNS Message", :email =>JSON.pretty_generate({"type" => "out","bucketname" => @aws_s3_bucketname,"channel"=>@channel,"path" => s3path}))
    ensure
      writer.close rescue nil
      tmp.close(true) rescue nil
    end
  end
  
  private
  
  def init_aws_s3_bucket
    unless @bucket
      options = {}
      options[:access_key_id]      = @aws_access_key_id
      options[:secret_access_key]  = @aws_secret_access_key
      options[:s3_endpoint]        = @aws_s3_endpoint
      options[:use_ssl]            = true
      s3 = AWS::S3.new(options)
      @bucket = s3.buckets[@aws_s3_bucketname]
    end
  end

  def init_aws_sns_topic
    unless @topic
      options = {}
      options[:access_key_id]     = @aws_access_key_id
      options[:secret_access_key] = @aws_secret_access_key
      options[:sns_endpoint]      = @aws_sns_endpoint
      sns = AWS::SNS.new(options)
      @topic = sns.topics[@aws_sns_topic_arn]
    end
  end

end