# XWiki Helm Chart

This is the XWiki [Helm Chart](https://helm.sh/docs/developing_charts) aiming to ease the deployment in both Local and Highly Available setups.  


## Resources

* XWiki Installation Guide: https://www.xwiki.org/xwiki/bin/view/Documentation/AdminGuide/Installation
* XWiki Docker : https://github.com/xwiki-contrib/docker-xwiki

## Installation on Minikube

* First, enable ingress

```bash
minikube addons enable ingress
```

* Setup Mysql

```bash
helm install --name mysql-xwiki --set mysqlRootPassword=xwiki,mysqlUser=xwiki,mysqlPassword=xwiki,mysqlDatabase=xwiki,imageTag=5.7 stable/mysql
```

* Install chart

```bash
git clone https://github.com/xwiki-contrib/xwiki-helm
cd xwiki-helm-chart
helm --debug upgrade -i --force xwiki -f ./values.yaml .
```

## Usage

Get ip address of minikube 

```bash
ip=$(minikube ip)
curl $ip
```

## Project informations

* Project Lead: [Ashish Sharma](https://www.xwiki.org/xwiki/bin/view/XWiki/ashish932)
* [Issue Tracker](http://jira.xwiki.org/browse/HELM)
* Communication: [Mailing List](http://dev.xwiki.org/xwiki/bin/view/Community/MailingLists), [IRC](http://dev.xwiki.org/xwiki/bin/view/Community/IRC)
* [Development Practices](http://dev.xwiki.org)
* Minimal XWiki version supported: XWiki 8.4
* License: LGPL 2.1
* Translations: N/A
* Sonar Dashboard: N/A
* Continuous Integration Status: N/A
