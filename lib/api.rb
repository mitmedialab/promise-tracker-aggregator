require 'sinatra'
require 'mongo'
require 'mongo_mapper'
require 'pry'
require 'json/ext'
require 'SecureRandom'

class Survey
  include MongoMapper::Document

  key :survey_id, Integer
  key :title, String
  key :status, String
  key :inputs, Array
end

class Response
  include MongoMapper::Document

  key :survey_id, Integer
  key :answers, Array
end

class PTApi < Sinatra::Base

  configure do
    MongoMapper.connection = Mongo::Connection.new('localhost', 27017)
    MongoMapper.database = 'pt-api'
  end

  before do
    headers 'Access-Control-Allow-Origin' => '*'
  end

  get '/surveys' do
    content_type :json
    Survey.all.to_json
  end

  post '/surveys' do
    data = JSON.parse(request.body.read)
    survey = Survey.create(data)
    survey.status = 'active'

    if survey.save
      {
        status: 'success',
        payload: { id: survey.id }
      }.to_json
    else
      {
        status: 'error',
        error_code: 13,
        error_message: "Survey could not be saved because id is already taken"
      }.to_json
    end
  end

  get '/surveys/:id' do
    content_type :json
    {
      status: 'success',
      payload: Survey.first(_id: params[:id].to_i)
    }.to_json
  end

  put '/surveys/:id/close' do
    survey = Survey.first(_id: params[:id].to_i)
    survey.status = 'closed'

    if survey.save
      { 
        status: 'success',
        payload: { id: survey.id }
      }.to_json
    else 
      { status: 'error' }.to_json
    end
  end

  get '/surveys/:id/responses' do
    content_type :json
    {
      status: 'success',
      payload: Response.all(survey_id: params[:id].to_i)
    }.to_json
  end

  get '/responses' do
    content_type :json
    {
      status: 'success',
      payload: Response.all
    }.to_json
  end

  post '/responses' do
    content_type :json
    response_data = JSON.parse(params[:response])
    if Survey.first(_id: response_data['survey_id'].to_i).status == 'active'
      {
        status: 'success',
        payload: Response.create(response_data)
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Response could not be posted because survey is closed'
      }.to_json
    end
  end

  post '/upload_image' do
    content_type :json
    @original_name = params[:file][:filename]
    @filename = SecureRandom.urlsafe_base64
    @filename = @filename + @original_name[@original_name.rindex('.')..-1]
    file = params[:file][:tempfile]
    begin
      File.open("./public/#{@filename}", 'wb') do |f|
        f.write(file.read)
        response = Response.find(params[:id])
        if response
          input_found = false
          input = response[:answers].select {|input| input['id']==params[:input_id].to_i}
          if input
            input[0]['value'] = @filename
            if response.save
              {
                status: 'success',
                payload: {id: params[:id], input_id: params[:input_id]}
              }.to_json
            else
              {
                status: 'error',
                error_code: 16,
                error_message: 'File Upload: cannot update response object'
              }.to_json
            end
          else
            {
              status: 'error',
              error_code: 15,
              error_message: 'File Upload: cannot find the corresponding input'
            }.to_json 
          end
        else
          {
            status: 'error',
            error_code: 14,
            error_message: 'File Upload: cannot find the response'
          }.to_json
        end
      end # post: file.open
    rescue IOError => e
      return {
        status: 'error',
        error_code: 17,
        error_message: 'File open failed'
      }.to_json
    ensure
      file.close unless file == nil
    end # post: try catch file.open error
  end # post: upload_image

end