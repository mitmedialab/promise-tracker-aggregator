require 'sinatra'
require 'mongo'
require 'mongo_mapper'
require 'pry'
require 'json/ext'

class Survey
  include MongoMapper::Document

  key :survey_id, Integer
  key :title, String
  key :inputs, Array
end

class Response
  include MongoMapper::Document

  key :survey_id, Integer
  key :answers, Array
end

class PTApi < Sinatra::Base

  configure do
    MongoMapper.connection = Mongo::Connection.new("localhost", 27017)
    MongoMapper.database = "pt-api"
  end

  before do
    headers 'Access-Control-Allow-Origin' => '*'
  end

  get '/responses' do
    content_type :json
    Response.all.to_json
  end

  post '/responses' do
    response_data = JSON.parse(params[:response])
    Response.create(response_data)
  end

  get '/surveys' do
    content_type :json
    Survey.all.to_json
  end

  get '/surveys/:id' do
    content_type :json
    Survey.first(_id: params[:id].to_i).to_json
  end

  post '/surveys' do
    data = JSON.parse(request.body.read)
    Survey.create(data)
  end

end