FROM ruby:2.6.5-slim
RUN apt-get update && apt-get install -y \
  build-essential \
  libxml2-dev \
  libxslt-dev \
  libmagic-dev \
  git \
  apt-transport-https \
  curl
RUN gem install bundler:2.1.4
RUN curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
RUN echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update && apt-get install -y --allow-unauthenticated kubectl
RUN mkdir /beekeeper
RUN mkdir ~/.kube/
COPY Gemfile /beekeeper/Gemfile
COPY Gemfile.lock /beekeeper/Gemfile.lock
WORKDIR /beekeeper
RUN bundle config set without 'development test'
RUN bundle install
COPY . /beekeeper
RUN rm -r .git

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0", "-e", "production"]
