# XWiki Helm Chart

This is the XWiki [Helm Chart](https://helm.sh/) aiming to ease the deployment in both Local and Highly Available setups.  


## Resources

* XWiki Installation Guide: https://www.xwiki.org/xwiki/bin/view/Documentation/AdminGuide/Installation
* XWiki Docker : https://github.com/xwiki-contrib/docker-xwiki

## Prerequisite

* Minikube
* Kubectl cli
* helm cli

## Installation on Minikube

* First, enable ingress

```bash
minikube addons enable ingress
```

* Install chart from helm source code

```bash
git clone https://github.com/xwiki-contrib/xwiki-helm
cd xwiki-helm-chart/charts/xwiki 
helm dependency update
helm --debug upgrade -i --force xwiki -f ./values.yaml .
```

* Install chart from repository 

```bash
helm repo add xwiki-helm https://xwiki-contrib.github.io./xwiki-helm 
# Use --devel install most recent released (beta/alpha) version
helm install --devel xwiki xwiki-helm/xwiki 
```

## Usage

Get ip address of minikube 

```bash
ip=$(minikube ip)
curl $ip
```

## Test

For testing first add [unittest](https://github.com/helm-unittest/helm-unittest#install)
```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
helm unittest charts/xwiki 
```

## Project Information

* Project Lead: [Ashish Sharma](https://www.xwiki.org/xwiki/bin/view/XWiki/ashish932)
* [Issue Tracker](http://jira.xwiki.org/browse/HELM)
* Communication: [Mailing List](http://dev.xwiki.org/xwiki/bin/view/Community/MailingLists), [IRC](http://dev.xwiki.org/xwiki/bin/view/Community/IRC)
* [Development Practices](http://dev.xwiki.org)
* Minimal XWiki version supported: XWiki 8.4
* License: LGPL 2.1
* Translations: N/A
* Sonar Dashboard: N/A
* Continuous Integration Status: N/A
