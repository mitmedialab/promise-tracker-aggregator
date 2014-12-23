require 'sinatra'
require 'mongo'
require 'mongo_mapper'
require 'pry'
require 'json/ext'

class Survey
  include MongoMapper::Document

  key :title, String
  key :code, Integer
  key :status, String
  key :start_date, Time
  key :inputs, Array

end

class Response
  include MongoMapper::Document

  key :survey_id, Integer
  key :answers, Array
end

class PTApi < Sinatra::Base

  configure do
    set :public_folder, File.dirname(__FILE__) + '/../public/'
    enable :static, :logging

    MongoMapper.connection = Mongo::Connection.new('localhost', 27017)
    MongoMapper.database = 'pt-api'
  end

  before do
    headers 'Access-Control-Allow-Origin' => '*'
    content_type 'application/json'
  end

  get '/surveys' do
    Survey.all.to_json
  end

  post '/surveys/:status' do
    data = JSON.parse(request.body.read)
    survey = Survey.first(id: data['id'])

    if survey
      survey.set(data)
    else
      survey = Survey.create(data)
    end

    survey.reload
    survey.status = params[:status]
    survey.start_date = Time.now.midnight
    Response.destroy_all({survey_id: survey.id})

    if survey.save
      {
        status: 'success',
        payload: { id: survey.id }
      }.to_json
    else
      {
        status: 'error',
        error_code: 13,
        error_message: 'Survey could not be saved because id is already taken'
      }.to_json
    end
  end

  get '/surveys/:code' do
    survey = Survey.first(code: params[:code].to_i)

    if survey
      {
        status: 'success',
        payload: survey
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  put '/surveys/:code/close' do
    survey = Survey.first(code: params[:code].to_i)
    
    if survey
      survey.status = 'closed'
      survey.save
      { 
        status: 'success',
        payload: { id: survey.id }
      }.to_json
    else 
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/surveys/:code/responses' do
    survey = Survey.first(code: params[:code].to_i)

    if survey
      {
        status: 'success',
        payload: Response.all(survey_id: survey.id)
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/surveys/:code/survey-with-responses' do
    survey = Survey.first(code: params[:code].to_i)

    if survey
      {
        status: 'success',
        payload: {
          survey: survey,
          responses: Response.all(survey_id: survey.id)
        }
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/responses' do
    {
      status: 'success',
      payload: Response.all
    }.to_json
  end

  post '/responses' do
    response_data = JSON.parse(params[:response])
    survey = Survey.first(_id: response_data['survey_id'].to_i)

    if survey
      if survey.status == 'active' || survey.status == 'test'
        response = Response.create(response_data)
        {
          status: 'success',
          payload: {id: response.id}
        }.to_json
      elsif survey.status == 'closed'
        {
          status: 'error',
          error_code: 14,
          error_message: 'Response could not be posted because survey is closed'
        }.to_json
      end
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  post '/upload_image' do
    original_name = params[:file][:filename]
    filename = SecureRandom.urlsafe_base64
    filename = filename + original_name[original_name.rindex('.')..-1]
    file = params[:file][:tempfile]

    begin
      File.open(settings.public_folder + filename, 'wb') do |f|
        f.write(file.read)
        response = Response.find(params[:id])
        if response
          input = response[:answers].select {|input| input['id'] == params[:input_id].to_i}
          if input
            input[0]['value'] = "#{request.base_url}/#{filename}"
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